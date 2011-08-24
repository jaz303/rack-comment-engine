require 'rubygems'
require 'rack'
require 'sqlite3'

require 'lib/comment_engine'

builder = Rack::Builder.new do
  use CommentEngine, :database => "test.db"
  run lambda { |env|
    [200, {"Content-Type" => "text/html"}, env.inspect]
  }
end
Rack::Handler::Mongrel.run builder, :Port => 4000
