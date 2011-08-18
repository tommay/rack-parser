require 'multi_json'
require 'multi_xml'

module Rack

  # Rack::Parser allows you to set custom parsers for incoming post body data. As a default,
  # Rack::Parser uses MultiJson and MultiXml to do the decoding/parsing for you. This allows you to
  # designate any engine you wish that is compatible with the MultiJson/MultiXml libraries.
  # You can also conveniently use another library by as well by wrapping it as a Proc or add additional
  # content types which are not default in this middleware.
  #
  class Parser

    # Rack Constants
    POST_BODY           = 'rack.input'.freeze
    FORM_INPUT          = 'rack.request.form_input'.freeze
    FORM_HASH           = 'rack.request.form_hash'.freeze

    # Default Settings
    DEFAULT_CONTENT_TYPE = {
      'application/xml'  => Proc.new { |body| MultiXml.parse(body)   },
      'application/json' => Proc.new { |body| MultiJson.decode(body) }
    }

    DEFAULT_ERROR_RESPONSE = {
      'default' =>
      Proc.new do |e, content_type|
        format = content_type.split('/').last
        meth   = "to_#{format}"
        meth   = "inspect" unless ::Hash.respond_to? meth
        [400, {'Content-Type' => content_type }, [ { 'errors' => e.to_s }.method(meth).call ] ]
      end
    }

    attr_reader :content_types, :error_responses

    # Usage:
    # use Rack::Parser, :content_types => {
    #   'application/xml'  => Proc.new { |body| XmlParser.parse body   } # if you don't want the default
    #   'application/json' => Proc.new { |body| JsonParser.decode body } # if you don't want the default
    #   'application/foo'  => Proc.new { |body| FooParser.parse body   } # Add custom content_types to parse.
    # }
    #
    # # use Rack::Parser,
    #   :content_types  => {
    #     'application/xml'  => Proc.new { |body| XmlParser.parse body   } # if you don't want the default
    #   },
    #   :error_reponses => {
    #     'default'          => Proc.new { |e, content_type, format| [500, {}, ["boo hoo"] ] },                         # Override the default error response..
    #     'application/json' => Proc.new { |e, content_type, format| [400, {'Content-Type'=>content_type}, ["broke"]] } # Customize error responses based on content type.
    #   }
    def initialize(app, options = {})
      @app             = app
      @content_types   = DEFAULT_CONTENT_TYPE.merge(options.delete(:content_types) || {})
      @error_responses = DEFAULT_ERROR_RESPONSE.merge(options.delete(:error_responses) || {})
    end

    def call(env)
      dup._call(env)
    end

    def _call(env)
      body = env[POST_BODY].read
      return @app.call(env) if (body.respond_to?(:empty?) ? body.empty? : !body) # Send it down the stack immediately
      content_type = Rack::Request.new(env).media_type
      begin
        result = @content_types[content_type].call(body)
        env.update FORM_HASH => result, FORM_INPUT => env[POST_BODY]
        @app.call env
      rescue Exception => e
        logger.warn "#{self.class} #{content_type} parsing error: #{e.to_s}" if respond_to? :logger # Send to logger if its there.
        err = @error_responses[content_type] ? content_type : 'default'
        @error_responses[err].call(e, content_type) # call the error responses
      end
    end

  end
end
