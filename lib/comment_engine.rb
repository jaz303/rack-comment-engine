require 'sqlite3'
require 'json'

class CommentEngine
  ENV_KEY = 'commentengine.thread'
  
  attr_reader :options
  
  def initialize(app, options = {})
    @app = app
    @options = {
      :base => '/comments',
      :email_required => true,
      :name_required => true,
      :auto_approve => true
    }.update(options)
  end
  
  def call(env)
    if env['REQUEST_URI'].index(base) == 0
      req = ::Rack::Request.new(env)
      case env['REQUEST_URI'][options[:base].length..-1]
      when /^\/threads\/([a-z0-9_-]+)$/i
        if req.get?
          find_thread($1)
        else
          method_not_allowed
        end
      when /^\/threads\/([a-z0-9_-]+)\/comments$/i
        if req.post?
          create_comment($1, req.params['comment'])
        else
          method_not_allowed
        end
      else
        not_found
      end
    else
      result = @app.call(env)
      create_thread(env[ENV_KEY]) if env[ENV_KEY]
      result
    end
  end
  
private
  def not_found
    [404, {"Content-Type" => "text/plain"}, "404 Not Found"]
  end

  def method_not_allowed
    [405, {"Content-Type" => "text/plain"}, "405 Method Not Allowed"]
  end
  
  def json_error(obj)
    [500, {"Content-Type" => "application/json"}, obj.to_json]
  end
  
  def json_ok(obj)
    [200, {"Content-Type" => "application/json"}, obj.to_json]
  end

  def base
    @options[:base]
  end
  
  def name_required?
    !! @options[:name_required]
  end
  
  def email_required?
    !! @options[:email_required]
  end
  
  def auto_approve?
    !! @options[:auto_approve]
  end

  def db
    unless @db
      @db = SQLite3::Database.new(options[:database])
      @db.type_translation = true
      @db.results_as_hash = true
      
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
    values = []
    values << ['closed', 0]
    
    if options[:slug]
      slug = options[:slug].to_s
      values << ['slug', "'#{q(slug.to_s)}'"] if slug.length > 0
    end
    
    if options[:auto_closes_at]
      time = options[:auto_closes_at]
      if time.is_a?(:string)
        time = q(time)
      else
        time = time.to_time if time.respond_to?(:to_time)
        time.utc
        time = time.strftime("%Y-%m-%dT%H:%M:%S")
      end
      values << ['auto_closes_at', "'#{time}'"]
    end
    
    db.execute <<-SQL
      INSERT INTO comment_thread
        (#{values.keys.join(', ')})
      VALUES
        (#{values.values.join(', ')})
    SQL
  end
  
  def find_thread(thread_id)
    row = find_thread_header(thread_id)
    
    if row.nil?
      not_found
    else
      row['comments'] = db.execute <<-SQL
        SELECT
          author_name, body, created_at
        FROM
          comment
        WHERE
          comment_thread_id = #{row['id'].to_i}
          AND hidden = 0
        ORDER BY
          created_at ASC
      SQL
      
      row['comments'].each { |c| treat!(c) }
      json_ok(row)
    end
  end
  
  def create_comment(thread_id, params)
    row = find_thread_header(thread_id)
    
    if row.nil?
      not_found
    else
      errors = {}
      
      author_name     = (params[:author_name] || '').to_s.strip
      author_email    = (params[:author_email] || '').to_s.strip
      body            = (params[:body] || '').to_s.strip
      
      if name_required? && author_name.length == 0
        errors['author_name'] = 'cannot be blank'
      end
      
      if author_email.length == 0
        if email_required?
          errors['author_email'] = 'cannot be blank'
        end
      elsif author_email !~ /^[^ @]+@[a-z0-9-]+(\.[a-z0-9-]+)+$/i
        errors['author_email'] = 'is not valid'
      end
      
      errors['body'] = 'cannot be blank' if body.length == 0
      errors['thread'] = 'is closed' if row['closed']
      
      if errors.empty?
        db.execute <<-SQL
          INSERT INTO comment
            (comment_thread_id, author_name, author_email, body, hidden)
          VALUES
            (#{row['id'].to_i}, '#{q(author_name)}', '#{q(author_email)}', '#{q(body)}', #{auto_approve? ? 0 : 1})
        SQL
        json_ok([true])
      else
        json_error(errors)
      end
    end
  end
  
  def find_thread_header(thread_id)
    thread_id = thread_id.to_s
    if thread_id =~ /^[0-9]/
      res = db.get_first_row("SELECT * FROM comment_thread WHERE id = #{thread_id.to_i}")
    else
      res = db.get_first_row("SELECT * FROM comment_thread WHERE slug = '#{q(thread_id)}'")
    end
    unless res.nil?
      treat!(res)
      res['closed'] = true if res['auto_closes_at'] && (Time.now > res['auto_closes_at'])
    end
    res
  end
  
  def treat!(hsh)
    # sqlite adds numeric indices to hashes because they want to be like php
    # undo the madness (57 is ascii '9')
    hsh.reject! { |k,v| k[0] <= 57 }
  end
  
  def q(str)
    SQLite3::Database.quote(str.to_s)
  end
end