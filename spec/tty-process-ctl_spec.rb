require_relative 'spec_helper'

describe TTYProcessCtl do
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
	end
end

