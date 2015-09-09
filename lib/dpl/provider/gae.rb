require 'yaml' # for parsing GAE's app.yaml

module DPL
  class Provider
    class GAE < Provider
      experimental 'Google App Engine'

      BASE='https://dl.google.com/dl/cloudsdk/channels/rapid/'
      NAME='google-cloud-sdk'
      EXT='.tar.gz'
      INSTALL='~'
      BOOTSTRAP="#{INSTALL}/#{NAME}/bin/bootstrapping/install.py"
      GCLOUD="#{INSTALL}/#{NAME}/bin/gcloud"

      # Indicates whether the invocation of gcloud preview app deploy should be wrapped
      # with aedeploy, which is specific to Managed VMs running the Go runtime.
      wrap = false

      def install_deploy_dependencies
        # FIXME this is a workaround for https://code.google.com/p/google-cloud-sdk/issues/detail?id=228
        if docker_build == "remote" && !File.exists?("#{Dir.home}/.ssh/google_compute_engine")
          unless context.shell('ssh-keygen -f ~/.ssh/google_compute_engine -t rsa -N \'\'')
            error 'Failed to generate SSH key for remote Docker build.'
          end
        end

        if File.exists? GCLOUD
          return
        end

        $stderr.puts 'Downloading Google Cloud SDK ...'

        unless context.shell("curl -L #{BASE + NAME + EXT} | gzip -d | tar -x -C #{INSTALL}")
          error 'Could not download Google Cloud SDK.'
        end

        $stderr.puts 'Bootstrapping Google Cloud SDK ...'

        unless context.shell("#{BOOTSTRAP} --usage-reporting=false --command-completion=false --path-update=false --additional-components=preview")
          error 'Could not bootstrap Google Cloud SDK.'
        end

        ay = YAML.load_file(config)
        if ay['runtime'] == 'go' && ay['vm'] == true
          wrap = true
          unless context.shell("go get google.golang.org/appengine/cmd/aedeploy")
            error 'Could not go get aedeploy.'
          end
        end
      end

      def needs_key?
        false
      end

      def check_auth
        unless context.shell("#{GCLOUD} -q --verbosity debug auth activate-service-account --key-file #{keyfile}")
          error 'Authentication failed.'
        end
      end

      def keyfile
        options[:keyfile] || context.env['GOOGLECLOUDKEYFILE'] || 'service-account.json'
      end

      def project
        options[:project] || context.env['GOOGLECLOUDPROJECT'] || context.env['CLOUDSDK_CORE_PROJECT'] || File.dirname(context.env['TRAVIS_REPO_SLUG'] || '')
      end

      def version
        options[:version] || ''
      end

      def config
        options[:config] || 'app.yaml'
      end

      def default
        options[:default]
      end

      def verbosity
        options[:verbosity] || 'warning'
      end

      def docker_build
        options[:docker_build] || 'remote'
      end

      def push_app
        command = wrap ? 'aedeploy ' : ''
        command << GCLOUD
        command << ' --quiet'
        command << " --verbosity \"#{verbosity}\""
        command << " --project \"#{project}\""
        command << " preview app deploy \"#{config}\""
        command << " --version \"#{version}\""
        command << " --docker-build \"#{docker_build}\""
        command << (default ? ' --set-default' : '')
        unless context.shell(command)
          error 'Deployment failed.'
        end
      end
    end
  end
end
