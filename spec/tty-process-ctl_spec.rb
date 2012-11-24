require_relative 'spec_helper'

describe TTYProcessCtl do
	subject do
		TTYProcessCtl.new('spec/stub')
	end

	after :each do
		subject.send_command 'stop' if subject.alive?
		subject.wait_exit
	end

	it 'should be Enumerable' do
		subject.should respond_to :take
		subject.take(2).should == ["151 recipes", "16 achievements"]
	end

	it 'should skip oldest messages if backlog queue is full' do
		subject = TTYProcessCtl.new('spec/stub', backlog_size: 2)

		subject.each_until(/Done/).to_a
		subject.send_command 'help'
		subject.send_command 'stop'

		# fait for backlog to overflow
		sleep 0.2

		subject.each.to_a.should == [
			"2011-09-19 22:12:00 [INFO] Saving chunks", 
			"2011-09-19 22:12:00 [INFO] Saving chunks"
		]
	end

	describe 'process output enumeration' do
		it 'should allow iterating the output lines' do
			subject.send_command 'stop'
			lines_count = 0
			subject.each do |line|
				lines_count += 1
			end
			lines_count.should == 23
		end
		
		it 'should allow iterating the output lines with enumerator' do
			subject.send_command 'stop'
			subject.each.to_a.length.should == 23
		end

		it 'should allow iteration until pattern is found in message' do
			subject.each_until(/NOT ENOUGH RAM/).to_a.last.should == "2011-09-10 12:58:55 [WARNING] **** NOT ENOUGH RAM!"
		end

		it 'should allow iteration until pattern is found in message excluding that message' do
			subject.each_until_exclude(/NOT ENOUGH RAM/).to_a.last.should == "2011-09-10 12:58:55 [INFO] Starting minecraft server version Beta 1.7.3"
		end

		it 'should allow waiting for message matching pattern' do
			subject.wait_until(/NOT ENOUGH RAM/)
			subject.send_command 'stop'
			subject.each.to_a.first.should == "2011-09-10 12:58:55 [WARNING] To start the server with more ram, launch it as \"java -Xmx1024M -Xms1024M -jar minecraft_server.jar\""
		end

		it 'should return nothing if iterating on dead process' do
			subject.send_command 'stop'
			subject.each.to_a.length.should == 23
			subject.should_not be_alive
			subject.each.to_a.should be_empty
		end

		it 'should allow flushing backlog messages' do
			subject.each_until(/SERVER IS RUNNING/).to_a
			sleep 0.2

			subject.flush

			subject.send_command 'list'
			subject.each_until(/Connected players/).to_a.should == ["2011-09-20 14:42:04 [INFO] Connected players: kazuya"]
		end
	end

	describe 'on message callbacks' do
		describe 'when enumerating' do
			it 'should call on message callback' do
				messages = []
				subject.on do |message|
					messages << message
				end

				subject.wait_until(/NOT ENOUGH RAM/)
				messages.should == [
					"151 recipes", 
					"16 achievements", 
					"2011-09-10 12:58:55 [INFO] Starting minecraft server version Beta 1.7.3", 
					"2011-09-10 12:58:55 [WARNING] **** NOT ENOUGH RAM!"
				]
			end

			it 'should call on message callback if given regexp matches the message' do
				messages = []
				subject.on(/recipes|achievements/) do |message|
					messages << message
				end

				subject.wait_until(/NOT ENOUGH RAM/)
				messages.should == [
					"151 recipes", 
					"16 achievements"
				]
			end
		end

		describe 'when polling' do
			it 'should call on message callback' do
				messages = []
				subject.on do |message|
					messages << message
				end

				subject.send_command 'stop'
				subject.poll!(timeout: 1.0)

				messages.length.should == 23
			end

			it 'should call on message callback if given regexp matches the message' do
				messages = []
				subject.on(/recipes|achievements/) do |message|
					messages << message
				end

					subject.send_command 'stop'
					subject.poll!(timeout: 1.0)

				messages.should == [
					"151 recipes", 
					"16 achievements"
				]
			end
		end

		describe 'when flushing' do
			it 'should call on message callback if given regexp matches the message' do
				messages = []
				subject.on(/recipes|achievements/) do |message|
					messages << message
				end

				sleep 1.0
				subject.flush

				messages.should == [
					"151 recipes", 
					"16 achievements"
				]
			end
		end

		describe 'closing' do
			it 'with close method on listener' do
				counter = 0
				listener = subject.on do
					counter += 1
				end

				subject.poll
				listener.close
				subject.poll

				counter.should == 1
			end

			it 'with break' do
				counter = 0
				subject.on do
					counter += 1
					break
				end

				subject.poll
				subject.poll

				counter.should == 1
			end
		end
	end

	describe 'sending commands' do
		it 'should allow sending commands to controled process' do
			subject.send_command 'stop'
			subject.each.to_a.last.should == "2011-09-19 22:12:00 [INFO] Saving chunks"
		end

		it 'should allow sending commands and iterating output' do
			subject.send_command 'list'
			subject.each_until(/Connected players/).to_a.last.should == "2011-09-20 14:42:04 [INFO] Connected players: kazuya"

			subject.send_command 'stop'
			subject.each.to_a.last.should == "2011-09-19 22:12:00 [INFO] Saving chunks"
		end

		it 'should not echo sent command' do
			subject.each_until(/Done/).to_a
			subject.send_command 'stop'
			subject.each.to_a.first.should_not == "stop"
		end

		it 'should raise error when sending command to dead process' do
			subject.send_command 'stop'
			subject.wait_exit

			expect {
				subject.send_command 'help'
			}.to raise_error IOError
		end
	end

	describe 'process status query' do
		it 'should allow querying if process is alive' do
			subject.should be_alive
			subject.send_command 'stop'
			subject.each.to_a
			subject.should_not be_alive
		end

		it 'should allow waiting for porcess to exit' do
			subject.should be_alive
			subject.send_command 'stop'
			subject.wait_exit
			subject.should_not be_alive
		end

		it 'should provide exit status when porcess exits' do
			subject.each_until(/Done/).to_a
			subject.exit_status.should be_nil

			subject.send_command 'stop'
			subject.each.to_a
			subject.exit_status.should be_a Process::Status
		end
	end

	describe 'timeout' do
		subject do
			# wait for process to be ready and delay each message printout by 0.1 second
			TTYProcessCtl.new('spec/stub --delay 0.01').wait_until(/151 recipes/, timeout: 1)
		end

		describe 'each calls with block' do
			it 'should raise TTYProcessCtl::Timeout on timieout' do
				expect {
					subject.each(timeout: 0.1){}
				}.to raise_error TTYProcessCtl::Timeout

				expect {
					subject.each_until(/bogous/, timeout: 0.1){}
				}.to raise_error TTYProcessCtl::Timeout

				expect {
					subject.each_until_exclude(/bogous/, timeout: 0.1){}
				}.to raise_error TTYProcessCtl::Timeout
			end

			it 'should not raise error if they return before timeout' do
				expect {
					subject.each_until(/achievements/, timeout: 1){}
				}.to_not raise_error TTYProcessCtl::Timeout

				expect {
					subject.each_until_exclude(/NOT ENOUGH RAM/, timeout: 1){}
				}.to_not raise_error TTYProcessCtl::Timeout

				expect {
					subject.each(timeout: 1) { break }
				}.to_not raise_error TTYProcessCtl::Timeout
			end
		end

		describe 'each calls with use of Enumerator object' do
			it 'should raise TTYProcessCtl::Timeout on timieout' do
				expect {
					subject.each(timeout: 0.1).to_a
				}.to raise_error TTYProcessCtl::Timeout

				expect {
					subject.each_until(/bogous/, timeout: 0.1).to_a
				}.to raise_error TTYProcessCtl::Timeout

				expect {
					subject.each_until_exclude(/bogous/, timeout: 0.1).to_a
				}.to raise_error TTYProcessCtl::Timeout
			end

			it 'should not raise error if they return before timeout' do
				expect {
					subject.each_until(/achievements/, timeout: 1).to_a
				}.to_not raise_error TTYProcessCtl::Timeout

				expect {
					subject.each_until_exclude(/NOT ENOUGH RAM/, timeout: 1).to_a
				}.to_not raise_error TTYProcessCtl::Timeout

				expect {
					subject.each(timeout: 1).first
				}.to_not raise_error TTYProcessCtl::Timeout
			end
		end

		describe 'wait calls' do
			it 'should raise TTYProcessCtl::Timeout on timieout' do
				expect {
					subject.wait_until(/bogous/, timeout: 0.1)
				}.to raise_error TTYProcessCtl::Timeout

				expect {
					subject.wait_exit(timeout: 0.1)
				}.to raise_error TTYProcessCtl::Timeout
			end

			it 'should not raise error if they return before timeout' do
				expect {
					subject.wait_until(/Done/, timeout: 1)
				}.to_not raise_error TTYProcessCtl::Timeout

				subject.send_command 'stop'

				expect {
					subject.wait_exit(timeout: 1)
				}.to_not raise_error TTYProcessCtl::Timeout
			end
		end
	end

	describe 'chaining' do
		it 'should work with each methods' do
			subject.send_command 'stop'
			subject.each_until(/recipes/){}.should == subject
			subject.each_until_exclude(/achievements/){}.should == subject
			subject.each{}.should == subject
		end
		
		it 'should work with wait methods' do
			subject.send_command 'stop'
			subject.wait_until(/Done/){}.should == subject
			subject.wait_exit{}.should == subject
		end

		it 'should work with flush method' do
			subject.flush.should == subject
		end
	end
end

