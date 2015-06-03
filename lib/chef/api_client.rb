#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Nuo Yan (<nuo@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/config'
require 'chef/mixin/params_validate'
require 'chef/mixin/from_file'
require 'chef/mash'
require 'chef/json_compat'
require 'chef/search/query'
require 'chef/exceptions'
require 'chef/versioned_rest'
require 'chef/mixin/api_version_request_handling'

class Chef
  class ApiClient

    include Chef::Mixin::FromFile
    include Chef::Mixin::ParamsValidate
    include Chef::VersionedRest
    include Chef::ApiVersionRequestHandling

    SUPPORTED_API_VERSIONS = [0,1]

    # Create a new Chef::ApiClient object.
    def initialize
      @name = ''
      @public_key = nil
      @private_key = nil
      @admin = false
      @validator = false
      @create_key = nil
    end

    def chef_rest_v0
      @chef_rest_v0 ||= get_versioned_rest_object(Chef::Config[:chef_server_url], "0")
    end

    def chef_rest_v1
      @chef_rest_v1 ||= get_versioned_rest_object(Chef::Config[:chef_server_url], "1")
    end

    # Gets or sets the client name.
    #
    # @params [Optional String] The name must be alpha-numeric plus - and _.
    # @return [String] The current value of the name.
    def name(arg=nil)
      set_or_return(
        :name,
        arg,
        :regex => /^[\-[:alnum:]_\.]+$/
      )
    end

    # Gets or sets whether this client is an admin.
    #
    # @params [Optional True/False] Should be true or false - default is false.
    # @return [True/False] The current value
    def admin(arg=nil)
      set_or_return(
        :admin,
        arg,
        :kind_of => [ TrueClass, FalseClass ]
      )
    end

    # Gets or sets the public key.
    #
    # @params [Optional String] The string representation of the public key.
    # @return [String] The current value.
    def public_key(arg=nil)
      set_or_return(
        :public_key,
        arg,
        :kind_of => String
      )
    end

    # Gets or sets whether this client is a validator.
    #
    # @params [Boolean] whether or not the client is a validator.  If
    #   `nil`, retrieves the already-set value.
    # @return [Boolean] The current value
    def validator(arg=nil)
      set_or_return(
        :validator,
        arg,
        :kind_of => [TrueClass, FalseClass]
      )
    end

    # Private key. The server will return it as a string.
    # Set to true under API V0 to have the server regenerate the default key.
    #
    # @params [Optional String] The string representation of the private key.
    # @return [String] The current value.
    def private_key(arg=nil)
      set_or_return(
        :private_key,
        arg,
        :kind_of => [String, TrueClass, FalseClass]
      )
    end

    # Used to ask server to generate key pair under api V1
    #
    # @params [Optional True/False] Should be true or false - default is false.
    # @return [True/False] The current value
    def create_key(arg=nil)
      set_or_return(
        :create_key,
        arg,
        :kind_of => [ TrueClass, FalseClass ]
      )
    end

    # The hash representation of the object. Includes the name and public_key.
    # Private key is included if available.
    #
    # @return [Hash]
    def to_hash
      result = {
        "name" => @name,
        "validator" => @validator,
        "admin" => @admin,
        'json_class' => self.class.name,
        "chef_type" => "client"
      }
      result["private_key"] = @private_key if @private_key
      result["public_key"] = @public_key if @public_key
      result["create_key"] = @create_key if @create_key
      result
    end

    # The JSON representation of the object.
    #
    # @return [String] the JSON string.
    def to_json(*a)
      Chef::JSONCompat.to_json(to_hash, *a)
    end

    def self.from_hash(o)
      client = Chef::ApiClient.new
      client.name(o["name"] || o["clientname"])
      client.admin(o["admin"])
      client.validator(o["validator"])
      client.private_key(o["private_key"]) if o.key?("private_key")
      client.public_key(o["public_key"]) if o.key?("public_key")
      client.create_key(o["create_key"]) if o.key?("create_key")
      client
    end

    def self.json_create(data)
      from_hash(data)
    end

    def self.from_json(j)
      from_hash(Chef::JSONCompat.parse(j))
    end

    def self.http_api
      Chef::REST.new(Chef::Config[:chef_server_url])
    end

    def self.reregister(name)
      api_client = load(name)
      api_client.reregister
    end

    def self.list(inflate=false)
      if inflate
        response = Hash.new
        Chef::Search::Query.new.search(:client) do |n|
          n = self.json_create(n) if n.instance_of?(Hash)
          response[n.name] = n
        end
        response
      else
        http_api.get("clients")
      end
    end

    # Load a client by name via the API
    def self.load(name)
      response = http_api.get("clients/#{name}")
      if response.kind_of?(Chef::ApiClient)
        response
      else
        json_create(response)
      end
    end

    # Remove this client via the REST API
    def destroy
      http_api.delete("clients/#{@name}")
    end

    # Save this client via the REST API, returns a hash including the private key
    def save
      begin
        http_api.put("clients/#{name}", { :name => self.name, :admin => self.admin, :validator => self.validator})
      rescue Net::HTTPServerException => e
        # If that fails, go ahead and try and update it
        if e.response.code == "404"
          http_api.post("clients", {:name => self.name, :admin => self.admin, :validator => self.validator })
        else
          raise e
        end
      end
    end

    def reregister
      reregistered_self = http_api.put("clients/#{name}", { :name => name, :admin => admin, :validator => validator, :private_key => true })
      if reregistered_self.respond_to?(:[])
        private_key(reregistered_self["private_key"])
      else
        private_key(reregistered_self.private_key)
      end
      self
    end

    # Create the client via the REST API
    def create
      payload = {
        :name => name,
        :validator => validator,
        # this field is ignored in API V1, but left for backwards-compat,
        # can remove after OSC 11 support is finished?
        :admin => admin
      }
      begin
        # try API V1
        raise Chef::Exceptions::InvalidClientAttribute, "You cannot set both public_key and create_key for create." if create_key && public_key

        payload[:public_key] = public_key if public_key
        payload[:create_key] = create_key if create_key

        new_client = chef_rest_v1.post("clients", payload)

        # get the private_key out of the chef_key hash if it exists
        if new_client['chef_key']
          if new_client['chef_key']['private_key']
            new_client['private_key'] = new_client['chef_key']['private_key']
          end
          new_client['public_key'] = new_client['chef_key']['public_key']
          new_client.delete('chef_key')
        end

        rescue Net::HTTPServerException => e
          # rescue API V0 if 406 and the server supports V0
          raise e unless handle_version_http_exception(e, SUPPORTED_API_VERSIONS[0], SUPPORTED_API_VERSIONS[-1])

          # under API V0, a key pair will always be created unless public_key is
          # passed on initial POST
          payload[:public_key] = public_key if public_key

          new_client = chef_rest_v0.post("clients", payload)
      end
      Chef::ApiClient.from_hash(self.to_hash.merge(new_client))
    end

    # As a string
    def to_s
      "client[#{@name}]"
    end

    # def inspect
    #   "Chef::ApiClient name:'#{name}' admin:'#{admin.inspect}' validator:'#{validator}' " +
    #   "public_key:'#{public_key}' private_key:'#{private_key}'"
    # end

    # TODO delete?
    def http_api
      @http_api ||= Chef::REST.new(Chef::Config[:chef_server_url])
    end

  end
end
