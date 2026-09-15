# © 2026 aiaiaiai · aiaiaiai.org
# SPDX-License-Identifier: Apache-2.0

module PrismHub
  module Domain
    # Ruby's freeze is shallow: freezing a Hash leaves every nested Hash, Array
    # and String inside it writable. A value object that only freezes its outer
    # container is immutable in name alone, so anything holding a reference can
    # still rewrite what it carries after construction.
    module DeepFreeze
      module_function

      def call(value)
        case value
        when Hash
          value.each do |key, nested|
            call(key)
            call(nested)
          end.freeze
        when Array
          value.each { call(_1) }.freeze
        else
          value.freeze
        end
      end
    end
  end
end
