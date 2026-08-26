# © 2026 aiaiaiai · aiaiaiai.org

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = true
  config.action_dispatch.show_exceptions = :rescuable
  config.active_support.deprecation = :stderr
  config.active_job.queue_adapter = :test
  config.log_level = :warn
end
