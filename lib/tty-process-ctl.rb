require 'thread'
require 'timeout'
require 'pty'
require 'io/console'

class TTYProcessCtl
	Timeout = Class.new(Timeout::Error)

	class Listener
		def initialize(&callback)
			@callback = callback
		end

		def call(message)
			@callback.call(message)
		rescue LocalJumpError => error
			# brake in listener
			close if error.reason == :break
		end

		def on_close(&callback)
			@on_close = callback unless closed?
			self
		end

		def close
			@on_close.call(self) if @on_close
			@closed = true
		end

		def closed?
			@closed
		end
	end

	include Enumerable

	def initialize(command, options = {})
		@backlog_size = options[:backlog_size] || 4000
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

	def on(regexp = nil, &callback)
		# return listender to user so he can close it after use
		listener do |message|
			next if regexp and message !~ regexp
			callback.call(message)
		end
	end

	def each(options = {}, &block)
		return enum_for(:each, options) unless block
		listener = listener(&block)
		begin
			timeout(options[:timeout]) do
				true while not listener.closed? and poll
			end
			self
		ensure
			# make sure we close the listener when each exits
			listener.close
		end
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
		poll!(options)
		@thread.join
		self
	end

	def poll(options = {})
		timeout(options[:timeout]) do
			return process_message
		end
	end

	def poll!(options = {})
		timeout(options[:timeout]) do
			true while process_message
		end
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

	def listener(&block)
		listener = Listener.new(&block).on_close do |listener|
			@listeners.delete(listener)
		end
		@listeners << listener
		listener
	end

	def process_message_no_block
		process_message(true)
	rescue ThreadError
		nil
	end

	def process_message(no_block = false)
		return nil if not alive? and @out_queue.empty?
		message = @out_queue.pop(no_block)
		return nil unless message
		message.freeze
		@listeners.each do |listener|
			listener.call(message)
		end
		message
	end

	def enqueue_message(message)
		@out_queue << message
		@out_queue.pop while @out_queue.length > @backlog_size
	end

	def enqueue_end
		@out_queue << nil
	end
end

