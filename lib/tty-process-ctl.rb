require 'thread'
require 'pty'

class TTYProcessCtl
	include Enumerable

	def initialize(command)
		@max_queue = 4000
		@command = command

		@out_queue = Queue.new
		@messages = []

		@r, @w, @pid = PTY.spawn(@command)
		@thread = Thread.start do
			abort_on_exception = true
			@r.each_line do |line|
				enqueue_message line
			end
			enqueue_control_message :exit
		end
	end

	def enqueue_message(message)
		@out_queue << message
		@out_queue.pop while @out_queue.length > @max_queue
	end

	def enqueue_control_message(message)
		@out_queue << message.to_sym
	end

	def alive?
		! PTY.check(@pid) and @thread.alive?
	end

	def send_command(command)
		@w.puts command
	end

	def messages
		@messages.join
	end

	def each
		return enum_for(:each) unless block_given?
		loop do
			break unless alive?
			message = @out_queue.pop
			break if message.is_a? Symbol and message == :exit
			@messages << message
			yield message 
		end
	end

	def each_until(pattern)
		each do |message|
			yield message
			break if message =~ pattern
		end
	end

	def each_until_exclude(pattern)
		each do |message|
			break if message =~ pattern
			yield message
		end
	end

	def flush
		loop do
			@messages << @out_queue.pop(true)
		end
	rescue ThreadError
	end
end

