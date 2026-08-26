# © 2026 aiaiaiai · aiaiaiai.org

namespace :prism_hub do
  desc "Check architecture, OpenAPI, and copyright contracts"
  task :check do
    %w[check_architecture check_contract check_copyright].each do |script|
      ruby File.expand_path("../../script/#{script}", __dir__)
    end
  end
end
