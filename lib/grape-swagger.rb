require 'kramdown'

module Grape
  class API
    class << self
      attr_reader :combined_routes
      alias original_mount mount

      def mount(mounts)
        original_mount mounts
        @combined_routes ||= {}
        mounts::routes.each do |route|
          resource = route.route_path.gsub("/#{settings[:root_prefix]}", '').match('\/(\w*?)[\.\/\(]').captures.first || '/'
          @combined_routes[resource.downcase] ||= []
          @combined_routes[resource.downcase] << route
        end
      end

      def add_swagger_documentation(options={})
        documentation_class = create_documentation_class

        documentation_class.setup({:target_class => self}.merge(options))
        mount(documentation_class)
      end

      private

      def create_documentation_class

        Class.new(Grape::API) do
          class << self
            def name
              @@class_name
            end
          end

          def self.setup(options)
            defaults = {
              :target_class => nil,
              :mount_path => '/swagger_doc',
              :base_path => nil,
              :api_version => '0.1',
              :markdown => false,
              :hide_documentation_path => false
            }
            options = defaults.merge(options)

            @@class_name = options[:class_name] || options[:mount_path].gsub('/','')
            @@target_class = options[:target_class]
            @@api_version = options[:api_version]

            mount_path = options[:mount_path]
            base_path = options[:base_path]
            root_prefix = @@target_class.settings[:root_prefix]

            desc 'Swagger compatible API description'
            get mount_path do
              header['Access-Control-Allow-Origin'] = '*'
              header['Access-Control-Request-Method'] = '*'
              routes = @@target_class::combined_routes

              if options[:hide_documentation_path]
                routes.reject!{ |route, value| "/#{route}/".index(parse_path(mount_path) << '/') == 0 }
              end

              routes_array = routes.keys.map do |route|
                { :path => "#{mount_path}/#{route}" }
              end

              computed_base_path = "#{request.base_url}#{'/' + base_path.gsub(/^\//, '') unless base_path.nil?}"
              computed_base_path = "#{computed_base_path}#{'/' + root_prefix unless root_prefix.nil?}"
              {
                apiVersion: @@api_version,
                swaggerVersion: "1.1",
                basePath: computed_base_path,
                operations:[],
                apis: routes_array
              }
            end

            desc 'Swagger compatible API description for specific API', :params =>
              {
                "name" => { :desc => "Resource name of mounted API", :type => "string", :required => true },
              }
            get "#{mount_path}/:name" do
              header['Access-Control-Allow-Origin'] = '*'
              header['Access-Control-Request-Method'] = '*'

              routes = @@target_class::combined_routes[params[:name]]
              routes_array = routes.map do |route|
                notes = route.route_notes && options[:markdown] ? Kramdown::Document.new(route.route_notes.strip_heredoc).to_html : route.route_notes
                {
                    :path => parse_path(route.route_path),
                    :operations => [{
                                        :notes => notes,
                                        :summary => route.route_description || '',
                                        :nickname   => route.route_method + (root_prefix.nil? ? route.route_path : route.route_path.gsub("/#{root_prefix}", '')).gsub(/[\/:\(\)\.]/,'-'),
                                        :httpMethod => route.route_method,
                                        :parameters => parse_header_params(route.route_headers) +
                                            parse_params(route.route_params, route.route_path, route.route_method)
                                    }]
                }
              end

              computed_base_path = "#{request.base_url}#{'/' + base_path.gsub(/^\//, '') unless base_path.nil?}"
              computed_base_path = "#{computed_base_path}#{'/' + root_prefix unless root_prefix.nil?}"
              {
                apiVersion: @@api_version,
                swaggerVersion: "1.1",
                basePath: computed_base_path,
                resourcePath: "",
                apis: routes_array
              }
            end
          end

          helpers do
            def parse_params(params, path, method)
              if params
                params.map do |param, value|
                  value[:type] = 'file' if value.is_a?(Hash) && value[:type] == 'Rack::Multipart::UploadedFile'

                  dataType = value.is_a?(Hash) ? value[:type]||'String' : 'String'
                  description = value.is_a?(Hash) ? value[:desc] : ''
                  required = value.is_a?(Hash) ? !!value[:required] : false
                  paramType = path.match(":#{param}") ? 'path' : (method == 'POST') ? 'body' : 'query'
                  name = (value.is_a?(Hash) && value[:full_name]) || param
                  {
                    paramType: paramType,
                    name: name,
                    description: description,
                    dataType: dataType,
                    required: required
                  }
                end
              else
                []
              end
            end

            def parse_header_params(params)
              if params
                params.map do |param, value|
                  dataType = 'String'
                  description = value.is_a?(Hash) ? value[:description] : ''
                  required = value.is_a?(Hash) ? !!value[:required] : false
                  paramType = "header"
                  {
                    paramType: paramType,
                    name: param,
                    description: description,
                    dataType: dataType,
                    required: required
                  }
                end
              else
                []
              end
            end

            def parse_path(path)
              root_prefix = @@target_class.settings[:root_prefix]

              # adapt format to swagger format
              parsed_path = path.gsub('(.:format)', '')
              # This is attempting to emulate the behavior of 
              # Rack::Mount::Strexp. We cannot use Strexp directly because 
              # all it does is generate regular expressions for parsing URLs. 
              # TODO: Implement a Racc tokenizer to properly generate the 
              # parsed path.
              parsed_path = parsed_path.gsub(/:([a-zA-Z_]\w*)/, '{\1}')
              # add the version
              parsed_path = parsed_path.gsub('{version}', @@api_version) if @@api_version
              parsed_path = parsed_path.gsub("/#{root_prefix}", '') if root_prefix
              parsed_path
            end
          end
        end
      end
    end
  end
end

class Object
  ##
  #   @person ? @person.name : nil
  # vs
  #   @person.try(:name)
  #
  # File activesupport/lib/active_support/core_ext/object/try.rb#L32
   def try(*a, &b)
    if a.empty? && block_given?
      yield self
    else
      __send__(*a, &b)
    end
  end
end

class String
  # strip_heredoc from rails
  # File activesupport/lib/active_support/core_ext/string/strip.rb, line 22
  def strip_heredoc
    indent = scan(/^[ \t]*(?=\S)/).min.try(:size) || 0
    gsub(/^[ \t]{#{indent}}/, '')
  end
end