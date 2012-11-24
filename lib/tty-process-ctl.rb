require 'thread'
require 'timeout'
require 'pty'
require 'io/console'

class TTYProcessCtl
	class Timeout < Timeout::Error
	end

	class Listener
		def initialize(&callback)
			@callback = callback
		end

		def call(message)
			@callback.call(message)
		end

		def on_close(&callback)
			@on_close = callback
			self
		end

		def close
			@on_close.call(self) if @on_close
		end
	end

	include Enumerable

	def initialize(command, options = {})
		@max_queue_length = options[:max_queue_length] || 4000
		@max_messages = options[:max_messages] || 4000
		@command = command
		@listeners = []

		@out_queue = Queue.new

		@r, @w, @pid = PTY.spawn(@command)
		@w.echo = false # disable echoing of commands
		@thread = Thread.start do
			begin
				abort_on_exception = true
				@r.each_line do |line|
					enqueue_message line.chop
				end
			rescue Errno::EIO
			ensure
				@exit_status = PTY.check(@pid)
				@r.close
				@w.close
				enqueue_end
			end
		end
	end

	attr_reader :exit_status

	def alive?
		@thread.alive?
	end

	def send_command(command)
		@w.puts command
	rescue Errno::EIO
		raise IOError.new("process '#{@command}' (pid: #{@pid}) not accepting input")
	end

	def each(options = {}, &block)
		return enum_for(:each, options) unless block

		listener = Listener.new(&block).on_close do |listener|
			@listeners.delete(listener)
		end
		@listeners << listener

		poll(options)
	ensure
		# one time use so close it after we have finished
		listener.close if listener
	end

	def each_until(pattern, options = {})
		return enum_for(:each_until, pattern, options) unless block_given?
		each(options) do |message|
			yield message
			break if message =~ pattern
		end
		self
	end

	def each_until_exclude(pattern, options = {})
		return enum_for(:each_until_exclude, pattern, options) unless block_given?
		each(options) do |message|
			break if message =~ pattern
			yield message
		end
		self
	end

	def wait_until(pattern, options = {})
		each_until(pattern, options){}
	end

	def wait_exit(options = {})
		poll(options)
		@thread.join
		self
	end

	def poll(options = {})
		timeout(options[:timeout]) do
			while !@out_queue.empty? or alive? do
				process_message || break
			end
		end
		self
	end

	def flush
		true while process_message_no_block
		self
	end

	private

	def timeout(t)
		yield unless t

		::Timeout::timeout(t, Timeout) do
			yield
		end
	end

	def process_message_no_block
		process_message(true)
	rescue ThreadError
		nil
	end

	def process_message(no_block = false)
		message = @out_queue.pop(no_block)
		return nil unless message
		@listeners.each do |listener|
			listener.call(message) or break
		end
		message
	end

	def enqueue_message(message)
		@out_queue << message
		@out_queue.pop while @out_queue.length > @max_queue_length
	end

	def enqueue_end
		@out_queue << nil
	end
end

