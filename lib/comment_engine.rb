require 'sqlite3'

class CommentEngine
  ENV_KEY = 'commentengine.thread'
  
  attr_reader :options
  
  def initialize(app, options = {})
    @app, @options = app, {:base => '/comments'}.update(options)
  end
  
  def call(env)
    if env['REQUEST_URI'].index(base) == 0
      p db
      [200, {"Content-Type" => "text/plain"}, "foobar"]
    else
      result = @app.call(env)
      create_thread(env[ENV_KEY]) if env[ENV_KEY]
      result
    end
  end
  
private

  def base
    @options[:base]
  end

  def db
    unless @db
      @db = SQLite3::Database.new(options[:database])
      
      @db.execute <<-CREATE
        CREATE TABLE IF NOT EXISTS comment_thread (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          slug VARCHAR(255) NULL,
          closed INTEGER NOT NULL DEFAULT 0,
          auto_closes_at DATETIME NULL
        );
      CREATE
      
      @db.execute <<-CREATE
        CREATE TABLE IF NOT EXISTS comment (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          comment_thread_id INTEGER NOT NULL,
          author_name VARCHAR(255) NOT NULL,
          author_email VARCHAR(255) NOT NULL,
          body TEXT NOT NULL,
          hidden BOOLEAN NOT NULL DEFAULT 0,
          created_at DATETIME NOT NULL DEFAULT (CURRENT_TIME)
        );
      CREATE
      
      @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS ct_slug ON comment_thread(slug)"
      @db.execute "CREATE INDEX IF NOT EXISTS c_thread_id ON comment(comment_thread_id)"
    end
    @db
  end
  
  def create_thread(options)
    
  end
  
  def find_comments_for_thread(thread_id)
    
  end
end