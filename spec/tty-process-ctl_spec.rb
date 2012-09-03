require_relative 'spec_helper'

describe TTYProcessCtl do
	subject do
		TTYProcessCtl.new('spec/stub')
	end

	describe 'process output enumeration' do
		subject do
			TTYProcessCtl.new('spec/stub --exit')
		end

		it 'should allow iterating the output lines' do
			lines_count = 0
			subject.each do |line|
				lines_count += 1
			end
			lines_count.should == 20
		end
		
		it 'should allow iterating the output lines with enumerator' do
			subject.each.to_a.length.should == 20
		end

		it 'should be Enumerable' do
			subject.should respond_to :take
			subject.take(2).should == ["151 recipes\r\n", "16 achievements\r\n"]
		end

		it 'should return nothing if iterating on dead process' do
			subject.each.to_a.length.should == 20
			subject.each.to_a.should be_empty
		end

		it 'should allow iteration until pattern is found in message' do
			subject.each_until(/NOT ENOUGH RAM/).to_a.last.should == "2011-09-10 12:58:55 [WARNING] **** NOT ENOUGH RAM!\r\n"
		end

		it 'should allow iteration until pattern is found in message excluding that message' do
			subject.each_until_exclude(/NOT ENOUGH RAM/).to_a.last.should == "2011-09-10 12:58:55 [INFO] Starting minecraft server version Beta 1.7.3\r\n"
		end

		it 'should allow waiting for message matching pattern' do
			subject.wait_until(/NOT ENOUGH RAM/)
			subject.each.to_a.first.should == "2011-09-10 12:58:55 [WARNING] To start the server with more ram, launch it as \"java -Xmx1024M -Xms1024M -jar minecraft_server.jar\"\r\n"
		end
	end

	describe 'sending commands' do
		it 'should allow sending commands to controled process' do
			subject.send_command 'stop'
			subject.each.to_a.last.should == "2011-09-19 22:12:00 [INFO] Saving chunks\r\n"
		end

		it 'should allow sending commands and iterating output' do
			subject.send_command 'list'
			subject.each_until(/Connected players/).to_a.last.should == "2011-09-20 14:42:04 [INFO] Connected players: kazuya\r\n"

			subject.send_command 'stop'
			subject.each.to_a.last.should == "2011-09-19 22:12:00 [INFO] Saving chunks\r\n"
		end

		it 'should echo sent command' do
			subject.each_until(/Done/).to_a
			subject.send_command 'stop'
			subject.each.to_a.first.should == "stop\r\n"
		end

		it 'should raise error when sending command to dead process' do
			subject.send_command 'stop'
			subject.wait_exit

			expect {
				subject.send_command 'help'
			}.to raise_error IOError
		end
	end

	describe 'messages' do
		subject do
			TTYProcessCtl.new('spec/stub --exit')
		end

		it 'should allow access to previously outputed messages' do
			subject.each.to_a
			subject.messages.length.should == 20
		end

		describe 'message flushing' do
			subject do
				TTYProcessCtl.new('spec/stub')
			end

			it 'should allow flushing queued messages before iteration' do
				subject.each_until(/SERVER IS RUNNING/).to_a
				sleep 0.2

				subject.flush

				subject.send_command 'list'
				subject.each_until(/Connected players/).to_a.should == ["list\r\n", "2011-09-20 14:42:04 [INFO] Connected players: kazuya\r\n"]

				subject.send_command 'stop'
			end
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

	describe 'limiting' do
		it 'should allow defining maximum number of messages that can be queued' do
			subject = TTYProcessCtl.new('spec/stub', max_queue_length: 2)

			subject.each_until(/Done/).to_a
			subject.send_command 'help'
			subject.send_command 'stop'

			sleep 0.2
			subject.each.to_a.length.should == 2
			subject.wait_exit
		end

		it 'should allow defining maximum number of messages that can be remembered' do
			subject = TTYProcessCtl.new('spec/stub', max_messages: 2)

			subject.each_until(/Done/).to_a
			subject.send_command 'help'
			subject.flush
			subject.send_command 'stop'
			subject.wait_exit

			subject.messages.length.should == 2
		end
	end

	describe 'timeout' do
		after :each do
			subject.send_command 'stop' if subject.alive?
			subject.wait_exit
		end

		describe 'each calls with block' do
			it 'should raise TTYProcessCtl::Timeout on timieout' do
				expect {
					subject.each(timeout: 0.1) {}
				}.to raise_error TTYProcessCtl::Timeout

				expect {
					subject.each_until(/bogous/, timeout: 0.1) {}
				}.to raise_error TTYProcessCtl::Timeout

				expect {
					subject.each_until_exclude(/bogous/, timeout: 0.1) {}
				}.to raise_error TTYProcessCtl::Timeout
			end

			it 'should not raise error if they return before timeout' do
				expect {
					subject.each_until(/recipes/, timeout: 1) {}
				}.to_not raise_error TTYProcessCtl::Timeout

				expect {
					subject.each_until_exclude(/achievements/, timeout: 1) {}
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
					subject.each_until(/recipes/, timeout: 1).to_a
				}.to_not raise_error TTYProcessCtl::Timeout

				expect {
					subject.each_until_exclude(/achievements/, timeout: 1).to_a
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
		subject do
			TTYProcessCtl.new('spec/stub --exit')
		end

		it 'should work with each methods' do
			subject.each_until(/recipes/){}.should == subject
			subject.each_until_exclude(/achievements/){}.should == subject
			subject.each{}.should == subject
		end
		
		it 'should work with wait methods' do
			subject.wait_until(/Done/){}.should == subject
			subject.wait_exit{}.should == subject
		end

		it 'should work with flush method' do
			subject.flush.should == subject
		end
	end
end

