require 'sqlite3'

class CommentEngine
  ENV_KEY = 'commentengine.thread'
  
  attr_reader :options
  
  class CommentThread
  end
  
  class Comment
  end
  
  def initialize(app, options = {})
    @app, @options = app, {:base => '/comments'}.update(options)
  end
  
  def call(env)
    if env['REQUEST_URI'].index(base) == 0
      p db
      [200, {"Content-Type" => "text/plain"}, "foobar"]
    else
      result = @app.call(env)
      if env[ENV_KEY]
        puts "creating a thread..."
      end
      result
    end
  end
  
private

  def base
    @options[:base]
  end

  def db
    @db ||= SQLite3::Database.new(options[:database])
  end
end