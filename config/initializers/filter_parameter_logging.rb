# © 2026 aiaiaiai · aiaiaiai.org

Rails.application.config.filter_parameters += [
  :authorization,
  :credential,
  :credential_ref,
  :password,
  :secret,
  :token
]
