require 'thread'
require 'pty'

class TTYProcessCtl
	include Enumerable

	def initialize(command, options = {})
		@max_queue_length = options[:max_queue_length] || 4000
		@max_messages = options[:max_messages] || 4000
		@command = command

		@out_queue = Queue.new
		@messages = []

		@r, @w, @pid = PTY.spawn(@command)
		@thread = Thread.start do
			begin
				abort_on_exception = true
				@r.each_line do |line|
					enqueue_message line
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

	def messages
		@messages
	end

	def each
		return enum_for(:each) unless block_given?
		while !@out_queue.empty? or alive? do
			yield (dequeue or break)
		end
	end

	def each_until(pattern)
		return enum_for(:each_until, pattern) unless block_given?
		each do |message|
			yield message
			break if message =~ pattern
		end
	end

	def each_until_exclude(pattern)
		return enum_for(:each_until_exclude, pattern) unless block_given?
		each do |message|
			break if message =~ pattern
			yield message
		end
	end

	def wait_exit
		each{}
		@thread.join
	end

	def wait_until(pattern)
		each_until(pattern){}
	end

	def flush
		loop do
			dequeue(true)
		end
	rescue ThreadError
	end

	private

	def dequeue(block = false)
		message = @out_queue.pop(block)
		return nil unless message
		@messages << message
		@messages.pop while @messages.length > @max_messages
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

