require 'thread'
require 'timeout'
require 'pty'
require 'io/console'

class TTYProcessCtl
	class Timeout < Timeout::Error
	end

	include Enumerable

	def initialize(command, options = {})
		@max_queue_length = options[:max_queue_length] || 4000
		@max_messages = options[:max_messages] || 4000
		@command = command

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

	def each(options = {})
		return enum_for(:each, options) unless block_given?
		timeout(options[:timeout]) do
			while !@out_queue.empty? or alive? do
				yield (dequeue or break)
			end
		end
		self
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
		each(options){}
		@thread.join
		self
	end

	def flush
		loop do
			dequeue(true)
		end
		self
	rescue ThreadError
		self
	end

	private

	def timeout(t)
		yield unless t

		::Timeout::timeout(t, Timeout) do
			yield
		end
	end

	def dequeue(no_block = false)
		message = @out_queue.pop(no_block)
		return nil unless message
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

