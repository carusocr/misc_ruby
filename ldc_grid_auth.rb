#!/usr/bin/env ruby
=begin
code for Sinatra grid connection

1. App accepts a user login/pass request.
2. Checks user's login info against values in extrawebs.spree_users.
3. If valid, redirects back to authorization app, which then allows user to click 'get token' button.
4. User clicks button, gets routed back to this app, which then returns the token string and expiration
   to the posting app.

Additional functions:

- Has a validate_token method that will check a token+corpus pair is valid in token table.

TODO:

Add HTTP status codes + response texts for validate_user method:

When a request fails, the resource server responds using the
   appropriate HTTP status code (typically, 400, 401, 403, or 405) and
   includes one of the following error codes in the response:

   invalid_request
         The request is missing a required parameter, includes an
         unsupported parameter or parameter value, repeats the same
         parameter, uses more than one method for including an access
         token, or is otherwise malformed.  The resource server SHOULD
         respond with the HTTP 400 (Bad Request) status code.

   invalid_token
         The access token provided is expired, revoked, malformed, or
         invalid for other reasons.  The resource SHOULD respond with
         the HTTP 401 (Unauthorized) status code.  The client MAY
         request a new access token and retry the protected resource
         request.

   insufficient_scope
         The request requires higher privileges than provided by the
         access token.  The resource server SHOULD respond with the HTTP
         403 (Forbidden) status code and MAY include the "scope"
         attribute with the scope necessary to access the protected
         resource.

   If the request lacks any authentication information (e.g., the client
   was unaware that authentication is necessary or attempted using an
   unsupported authentication method), the resource server SHOULD NOT
   include an error code or other error information.

   For example:

     HTTP/1.1 401 Unauthorized
     WWW-Authenticate: Bearer realm="example"

=end


require 'sinatra'
require 'thin'
require 'sinatra/json'
require 'sequel'
require 'haml'
require 'yaml'
require 'json'

class MyThinBackend < ::Thin::Backends::TcpServer
  def initialize(host, port, options)
    super(host, port)
    @ssl = true
    @ssl_options = options
  end
end
 
configure do
  set :environment, :production
  set :bind, '0.0.0.0'
  #set :bind, '128.91.252.177'
  set :port, 4567
  set :server, "thin"
  class << settings
    def server_settings
      {
        :backend          => MyThinBackend,
        :private_key_file => '/etc/ssl/gridauth/gridauth.key',
        :cert_chain_file  => '/etc/ssl/gridauth/gridauth.cer',
        :verify_peer      => false
      }
    end
  end
  # added logging + stdout feed
  file = File.new('gridauth.log','a+')
  file.sync = true
  use Rack::CommonLogger, file
end

#db connection info stored in 600-permed yaml file
cfgfile = '.grid_auth.yml'
$cnf = YAML::load(File.open(cfgfile))
$pepper = $cnf['sha512']['pepper']

def set_and_connect_to_db(mode)
  $db_pwd = $cnf[mode]['password']
  $db_username = $cnf[mode]['username']
  $db = $cnf[mode]['database']
  $db_host = $cnf[mode]['hostname']
  $dbh = Sequel.connect(:adapter => 'mysql2', :host => $db_host, :user => $db_username, :database => $db, :password => $db_pwd) 
end

def validate_token(token,corpus)
  # First, connect to tokens table and get org id...
  set_and_connect_to_db("grid_readonly")
  tokens = $dbh.from(:tokens).where(:token => token)
  #return 401 if tokens.first.nil?
  if tokens.first.nil?
    puts 'nil token response'
    return Rack::Response.new('',401,{"error" => "invalid_token"}).finish
  end
  if tokens.where('token = ? and expires_at > current_timestamp',token).count == 1
    puts 'token fits and is good'
    #run corpus check here
    user_org = tokens.first[:organization_id]
    puts "User org is #{user_org}"
    $dbh.disconnect
    puts "Checking for corpus #{corpus}"
    set_and_connect_to_db("ldc_membership")
    corpora = get_org_corpora(user_org)
    puts "Allowed corpora: #{corpora.inspect}"
    if !corpora.include? corpus
      puts 'corpus bad'
      status = Rack::Response.new('',403,{"error" => "invalid_scope"}).finish
    else
      puts 'everything ok'
      status = 200
    end
  else #no or expired token
    return Rack::Response.new('',401,{"error" => "invalid_token"}).finish
  end
  return status
  $dbh.disconnect
end

def validate_user(username,password)
  set_and_connect_to_db("ldc_membership")
  users = $dbh[:spree_users].where(:login=>username).all
  if users.first.nil?     #if no results
    puts 'failed at membership query'
    $dbh.disconnect
    return JSON.generate({:corpus => nil, :status => 401})
  else
    if users.first[:encrypted_password] == Digest::SHA1.hexdigest(password)
      puts "old style password!"
    else
      puts "new style password!"
      salt = users.first[:password_salt]
      encrypted_password = regurgitate_new_pwd(password,salt,$pepper)
      if users.first[:encrypted_password] != encrypted_password
        $dbh.disconnect
        return JSON.generate({:corpus => nil, :status => 401})
      end
    end
    user_org = users.first[:organization_id]
  end
  # if ok, pass corpus info to token generation and return 200
  $dbh.disconnect
  set_and_connect_to_db("grid_readonly")
  token_string = SecureRandom.uuid
  timestamp = Sequel.lit('date_add(current_timestamp,interval 8 hour)') 
  tokens = $dbh.from(:tokens)
  begin
    tokens.insert(:token => token_string, :expires_at => timestamp, :organization_id => user_org)
  rescue => e
    status = 400
    puts 'failed at token insert'
    puts e.message
  end
  status = 200
  return JSON.generate({:access_token => token_string, :status => status})
end

def get_org_corpora(organization_id)
#gridauth version
  corpus_query = "SELECT spree_products.permalink "\
  " FROM spree_orders LEFT JOIN spree_line_items" \
  " ON spree_line_items.order_id=spree_orders.id"\
  " INNER JOIN spree_variants ON spree_variants.id=spree_line_items.variant_id"\
  " INNER JOIN spree_products ON spree_products.id=spree_variants.product_id"\
  " WHERE spree_orders.organization_id=?"\
  " AND spree_products.product_type = 'corpus'"\
  " AND spree_orders.completed_at IS NOT NULL"
  # populate array with query result
  corpora = $dbh[corpus_query, organization_id].map {|h| h[:permalink]}
  return corpora
end

def regurgitate_new_pwd(password, salt, pepper)
  stretches = 20
  digest = [password,salt].flatten.join('')
  stretches.times { digest = Digest::SHA512.hexdigest(digest) }
  digest
end

get '/' do
  $redirect_uri = params[:redirect_uri]
  haml :login
end

post '/' do

  grant_type = params[:grant_type]
  code = params[:code]  #tmp auth code passed by lappsgrid app

  if grant_type == 'authorization_code'
    # check to make sure that code passed to app links to token
		return status 401 if $token_hash.nil?
    return status 401 unless $token_hash[$token] == code
    puts 'authcode from post /'
    puts $token
    content_type :json
    if $token.nil?
      json :status => 201
    else
			puts "token not nil, generating json"
      msgbody = json :access_token => $token["access_token"], :expires_in => 28800
      #json :access_token => $token, :status => 222, :expires_in => 28800
      puts $token
      #reset token here for security?
      $token=nil
    	response = Rack::Response.new(msgbody,200)
    	return response.finish
    end
  else
    #return status 201
    content_type :json
    json :status => 201
  end

end

post '/new' do

  if $redirect_uri.nil?
    return status 201
  else #if someone posts a new with non-auth grant type, check their credentials and redirect
    $token = JSON.parse(validate_user(params[:username],params[:password]))
    puts $token["status"]
    redirect to('/') if $token["status"] == 401
    puts "redirecting to #{$redirect_uri}"
    tmp_code = SecureRandom.uuid
    # redirect to needs to pass a code value - UID unique value, something that gets used once
    # add hash to map each code to a specific token
    $token_hash = Hash.new
    $token_hash[$token]=tmp_code
    redirect to("#{$redirect_uri}?code=#{tmp_code}")
  end

end

post '/validate' do
  # if no token + corpus value is provided, return noninformative 401
  if (params[:token].nil? or params[:corpus].nil?)
    puts 'no params'
    response = Rack::Response.new('',401)
    return response.finish
  else
    token_status = validate_token(params[:token],params[:corpus])
    status token_status
  end
end
