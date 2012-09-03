#!/usr/bin/env ruby
require_relative '../lib/tty-process-ctl'

TTYProcessCtl.new('echo "abc\ndef\nghi"').wait_until(/def/).each do |line|
	puts line
end

