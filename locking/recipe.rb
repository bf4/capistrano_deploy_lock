Capistrano::Configuration.instance(:must_exist).load do
  before "deploy:update_code",    "deploy:check_lock"
  before "deploy:update_code",    "deploy:refresh_lock"
  before "deploy:update_code",    "deploy:create_lock"
  after  "deploy:create_symlink", "deploy:unlock"
  before 'deploy:rollback',       'deploy:unlock'

  # Default lock expiry of 15 minutes (in case deploy crashes or is interrupted)
  _cset :default_lock_expiry, (15 * 60)
  _cset(:deploy_lockfile) { "#{shared_path}/capistrano.lock.yml" }

  # Show lock message as bright red
  log_formatter(:match => /was locked/, :color => :red, :style => :bright, :priority => 20)

  namespace :deploy do
    # Fetch the deploy lock unless already cached
    def fetch_deploy_lock
      if self[:deploy_lock].nil?
        lock_file = capture("[ -e #{deploy_lockfile} ] && cat #{deploy_lockfile} || true").strip
        if lock_file != ""
          set :deploy_lock, YAML.load(lock_file)
        else
          set :deploy_lock, false
        end
      end
    end

    def write_deploy_lock(deploy_lock)
      put deploy_lock.to_yaml, deploy_lockfile, :mode => 0777
      # Ensure the lockfile is removed on failure
      at_exit { exit_cleanup('exception on exit') if $! }
      trap('INT') { exit_cleanup('interrupt'); exit 1 }
      on_rollback { exit_cleanup('rollback') }
    end

    def exit_cleanup(reason)
      if @already_removed_lock
        logger.info "[#{reason}] already removed lock"
      else
        logger.important "[#{reason}] Deploy failure, removing lockfile"
        remove_deploy_lock
        @already_removed_lock = true
      end
    end

    def remove_deploy_lock
      run "rm -f #{deploy_lockfile}"
    end

    desc "Deploy with a custom deploy lock"
    task :with_lock do
      lock
      deploy.default
    end

    desc "Set deploy lock with a custom lock message and expiry time"
    task :lock do
      set :lock_message, Capistrano::CLI.ui.ask("Lock Message: ")

      while self[:lock_expiry].nil?
        expiry_str = Capistrano::CLI.ui.ask("Expire lock at? (optional): ")
        if expiry_str == ""
          # Never expire an explicit lock if no time given
          set :lock_expiry, false
        else
          parsed_expiry = nil
          if defined?(Chronic)
            parsed_expiry = Chronic.parse(expiry_str) || Chronic.parse("#{expiry_str} from now")
          elsif dt = (DateTime.parse(expiry_str) rescue nil)
            parsed_expiry = dt.to_time
          end

          if parsed_expiry
            set :lock_expiry, parsed_expiry.utc
          else
            logger.info "'#{expiry_str}' could not be parsed. Please try again."
          end
        end
      end

      create_lock
      set :custom_deploy_lock, true
    end

    desc "Creates a lock file, so that futher deploys will be prevented"
    task :create_lock do
      if self[:custom_deploy_lock]
        logger.info 'Custom deploy lock already created.'
        next
      end

      if self[:lock_message].nil?
        set :lock_message, "Deploying #{branch} branch"
      end
      if self[:lock_expiry].nil?
        set :lock_expiry, (Time.now + default_lock_expiry).utc
      end

      deploy_lock = {
        :created_at => Time.now.utc,
        :username   => ENV['USER'],
        :expire_at  => self[:lock_expiry],
        :message    => self[:lock_message]
      }
      write_deploy_lock(deploy_lock)
    end

    namespace :unlock do
      desc "Unlocks the server for deployment"
      task :default do
        # Don't automatically remove custom deploy locks created by deploy:lock task
        if self[:custom_deploy_lock]
          logger.info 'Not removing custom deploy lock.'
        else
          remove_deploy_lock
        end
      end

      task :force do
        remove_deploy_lock
      end
    end

    desc "Checks for a deploy lock. If present, deploy is aborted and message is displayed. Any expired locks are deleted."
    task :check_lock do
      # Don't check the lock if we just created it
      next if self[:custom_deploy_lock]

      fetch_deploy_lock
      # Return if no lock
      next unless self[:deploy_lock]

      if deploy_lock[:expire_at] && deploy_lock[:expire_at] < Time.now
        logger.info "Deleting expired deploy lock..."
        unlock
        next
      end

      # Unexpired lock is present, so display the lock message
      logger.important Capistrano::DeployLock.message(application, stage, deploy_lock)

      # Don't raise exception if current user owns the lock.
      # Just sleep so they have a chance to Ctrl-C
      if deploy_lock[:username] == ENV['USER']
        4.downto(1) do |i|
          Kernel.print "\rDeploy lock was created by you (#{ENV['USER']}). Continuing deploy in #{i}..."
          sleep 1
        end
        puts
      else
        raise Capistrano::DeployLockedError
      end
    end

    desc "Refreshes an existing deploy lock's expiry time, if it is less than the default time"
    task :refresh_lock do
      # Don't refresh custom locks
      next if self[:custom_deploy_lock]

      fetch_deploy_lock
      next unless self[:deploy_lock]

      # Refresh lock expiry time if it's going to expire soon
      if deploy_lock[:expire_at] && deploy_lock[:expire_at] < (Time.now + default_lock_expiry)
        logger.info "Resetting lock expiry to default..."
        deploy_lock[:expire_at] = (Time.now + default_lock_expiry).utc

        write_deploy_lock(deploy_lock)
      end

      # Set the deploy_lock_created flag so that the lock isn't automatically removed after deploy
      set :custom_deploy_lock, true
    end
  end
end
