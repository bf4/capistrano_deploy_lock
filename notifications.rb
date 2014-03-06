module Capistrano
  module DeployNotifications
    DELIVERY_SETTINGS = {
      :delivery_method => :smtp,
      :smtp_settings = {
            return_path: 'from@example.com',
            address: 'gateway',
            port: 587,
            domain: 'domain',
            authentication: "plain",
            enable_starttls_auto: true
      },
      :notification_address => 'notify@example.com',
      :app_name => Rails.application.class.parent.name,
    }

    def self.load_into(configuration)
      configuration.load do
        after 'deploy:create_lock', 'deploy:notify:start'
        after 'deploy:unlock', 'deploy:notify:end'

        namespace :deploy do
          namespace :notify do
            desc 'Deploy start'
            task :start do
              STDOUT.puts "[Deploy Start] #{current_time}"
              begin
                cdnotify.deploy_notification(DELIVERY_SETTINGS[:notification_address], cdnotify).deliver
              rescue Exception => e
                STDERR.puts e.inspect
              end
            end
            desc 'Deploy end'
            task :end do
              STDOUT.puts "[Deploy End] #{current_time}"
            end
            def current_time
              Time.now.to_s(:ymdhms_tz)
            end
          end
        end
      end
    end

    def deploy_notification(recipient, notifier)
      require 'mail'
      Mail.defaults do
        delivery_method DELIVERY_SETTINGS[:delivery_method], DELIVERY_SETTINGS[:smtp_settings]
      end
      mail = Mail.new do
        from DELIVERY_SETTINGS[:smtp_settings][:return_path]
        to recipient
        subject    "[#{notifier.current_time}] #{DELIVERY_SETTINGS[:app_name]} Deployed by #{`whoami`.strip}!"
body <<-MSG
  Hello. This is to inform you
  that a deployment has happened to
  at #{notifier.current_hash} with the changes:

#{notifier.change_log}
MSG
      end
      mail
    end

    def current_time
      Time.now.to_s(:ymdhms_local)
    end

    # see http://stackoverflow.com/questions/1404796/how-to-get-the-latest-tag-name-in-current-branch-in-git
    # see https://www.kernel.org/pub/software/scm/git/docs/git-for-each-ref.html
    # see https://www.kernel.org/pub/software/scm/git/docs/git-describe.html
    # see https://www.kernel.org/pub/software/scm/git/docs/git-log.html
    def change_log
      last_deploy_tag = `git for-each-ref #{pattern} --sort=-taggerdate --format='%(objectname:short)' --count=1`.strip
      `git log --pretty='%d %s <%an>' --abbrev-commit --graph --decorate #{last_deploy_tag}..HEAD`.strip
    end

    # matches either tags starting with the stage name
    # or containing 'ruby' e.g.
    # refs/tags/cruby* or ref/tags/*ruby*
    def pattern
      "refs/tags/#{defined?(stage) ? stage : '*ruby'}*"
    end

    def current_hash
      `git describe`.strip
    end

  end
end
Capistrano.plugin :cdnotify, Capistrano::DeployNotifications

if Capistrano::Configuration.instance
  Capistrano::DeployNotifications.load_into(Capistrano::Configuration.instance(:must_exist))
end
