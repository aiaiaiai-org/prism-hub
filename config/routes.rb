# © 2026 aiaiaiai · aiaiaiai.org

require "prism_hub"

Rails.application.routes.draw do
  mount PrismHub::Bootstrap.build(env: ENV, logger: Rails.logger), at: "/"
end
