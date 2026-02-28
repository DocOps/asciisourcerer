# frozen_string_literal: true

require_relative '../../../lib/sourcerer'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
