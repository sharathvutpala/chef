#
# Author:: Steven Danna (<steve@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
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

require 'chef/knife'

class Chef
  class Knife
    class UserList < Knife

      deps do
        require 'chef/user'
        require 'chef/json_compat'
      end

      banner "knife user list (options)"

      option :with_uri,
        :short => "-w",
        :long => "--with-uri",
        :description => "Show corresponding URIs"

      def osc_11_warning
<<-EOF
knife user list failed in a way that indicates that you are using an Open Source 11 Server.
knife user list for Open Source 11 Server is being deprecated.
Open Source 11 Server user commands now live under the knife opc_user namespace.
For backwards compatibility, we will forward this request to knife osc_user list.
If you are using an Open Source 11 Server, please use that command to avoid this warning.
EOF
      end

      def run_osc_11_user_list
        Chef::Knife.run(ARGV, Chef::Application::Knife.options)
      end

      def run
        begin
          output(format_list_for_display(Chef::User.list))
        # delete this rescue once OSC11 support is gone
        rescue TypeError => e
          raise e unless /no implicit conversion of String into Integer/.match(e.message)

          # if we've made it here, then the Chef Server is likely OSC 11, forward the request
          ui.warn(osc_11_warning)

          # run osc_user_list with our input
          ARGV.delete("user")
          ARGV.unshift("osc_user")
          run_osc_11_user_list
        end
      end
    end
  end
end
