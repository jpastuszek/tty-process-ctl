#!/usr/bin/env ruby
require_relative '../lib/tty-process-ctl'

TTYProcessCtl.new('ls').each do |line|
	puts line
end

