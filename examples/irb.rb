#!/usr/bin/env ruby
require_relative '../lib/tty-process-ctl'

irb = TTYProcessCtl.new('irb')

# send command
irb.send_command('2 + 2')

# wait until prompt line was printed
irb.wait_until(/:001 >/)

# print all output lines until we get to the result line (including) 
irb.each_until(/=>/) do |line|
	puts line
end

# ask irb to quit
irb.send_command('quit')

# wait irb to exit
irb.wait_exit

