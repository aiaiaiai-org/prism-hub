# © 2026 aiaiaiai · aiaiaiai.org

module PrismHub
  module Adapters
    # AIS's Ed25519 signing keys from its public JWKS, cached. An unknown key id refreshes the
    # cache, at most once a minute, so a rotated key is picked up without a restart and a flood
    # of made-up key ids cannot turn Hub into a client that hammers AIS.
    class HttpAisKeySource < Ports::AisKeySource
      CACHE_SECONDS = 300
      MIN_REFRESH_SECONDS = 60
      TIMEOUT_SECONDS = 5
      MAX_BODY_BYTES = 65_536

      def initialize(issuer:, fetch: nil, logger: nil)
        @uri = URI("#{issuer}/.well-known/jwks.json")
        @fetch = fetch || method(:fetch_over_https)
        @logger = logger
        @keys = {}
        @fetched_at = nil
        @mutex = Mutex.new
      end

      def key(kid:, now:)
        @mutex.synchronize do
          refresh(now) if stale?(now) || (!@keys.key?(kid) && refresh_allowed?(now))
          @keys[kid]
        end
      end

      private

      def stale?(now)
        @fetched_at.nil? || now - @fetched_at >= CACHE_SECONDS
      end

      def refresh_allowed?(now)
        @fetched_at.nil? || now - @fetched_at >= MIN_REFRESH_SECONDS
      end

      def refresh(now)
        @fetched_at = now
        body = @fetch.call(@uri)
        keys = parse(body)
        @keys = keys if keys
      rescue StandardError => error
        # Keep the keys already known: an unreachable AIS must not sign every product out of Hub
        # for the length of the outage.
        @logger&.warn("hub_ais_jwks_unavailable error_class=#{error.class.name}")
      end

      def parse(body)
        return nil if body.nil? || body.bytesize > MAX_BODY_BYTES

        document = JSON.parse(body)
        return nil unless document.is_a?(Hash) && document["keys"].is_a?(Array)

        document["keys"].each_with_object({}) do |entry, keys|
          next unless entry.is_a?(Hash)
          next unless entry["kty"] == "OKP" && entry["crv"] == "Ed25519"
          next unless entry["kid"].is_a?(String) && entry["x"].is_a?(String)

          raw = Base64.urlsafe_decode64(entry["x"])
          next unless raw.bytesize == 32

          keys[entry["kid"]] = OpenSSL::PKey.new_raw_public_key("ED25519", raw)
        rescue ArgumentError, OpenSSL::PKey::PKeyError
          next
        end.freeze
      rescue JSON::ParserError
        nil
      end

      def fetch_over_https(uri)
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: true,
          open_timeout: TIMEOUT_SECONDS,
          read_timeout: TIMEOUT_SECONDS
        ) { |http| http.get(uri.request_uri, "accept" => "application/json") }
        raise "AIS JWKS answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      end
    end
  end
end
