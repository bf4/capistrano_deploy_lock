# Capistrano Deploy Lock
# Version 1.1.0
# Copied from https://github.com/ndbroadbent/capistrano_deploy_lock
# Based on deploy_lock.rb from https://github.com/bokmann/dunce-cap

require 'time'
# Provide advanced expiry time parsing via Chronic, if available
begin; require 'chronic'; rescue LoadError; end
begin
  # Use Rails distance_of_time_in_words_to_now helper if available
  require 'action_view'
  require File.expand_path('../locking/date_helper', __FILE__)
rescue LoadError
end

module Capistrano
  DeployLockedError = Class.new(StandardError)

  module DeployLock
    def self.message(application, stage, deploy_lock)
      message = "#{application} (#{stage}) was locked"
      if defined?(Capistrano::DateHelper)
        locked_ago = Capistrano::DateHelper.distance_of_time_in_words_to_now deploy_lock[:created_at].localtime
        message << " #{locked_ago} ago"
      else
        message << " at #{deploy_lock[:created_at].localtime}"
      end
      message << " by '#{deploy_lock[:username]}'\nMessage: #{deploy_lock[:message]}"

      if deploy_lock[:expire_at]
        if defined?(Capistrano::DateHelper)
          expires_in = Capistrano::DateHelper.distance_of_time_in_words_to_now deploy_lock[:expire_at].localtime
          message << "\nExpires in #{expires_in}"
        else
          message << "\nExpires at #{deploy_lock[:expire_at].localtime.to_s(:hms)}"
        end
      else
        message << "\nLock must be manually removed with: cap #{stage} deploy:unlock"
      end
    end
  end
end

# Load recipe if required from deploy script
if defined?(Capistrano::Configuration) && Capistrano::Configuration.instance
  require File.expand_path('../locking/recipe', __FILE__)
end
