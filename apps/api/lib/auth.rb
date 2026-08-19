# frozen_string_literal: true

require 'json'
require 'cgi'
require_relative 'chatwoot_client'
require_relative 'errors'

module Nex
  class Auth
    COOKIE_NAME = 'cw_d_session_info'

    def initialize(env)
      @env = env
    end

    def session
      @session ||= begin
        client = ChatwootClient.new(
          base_url: ENV.fetch('CHATWOOT_INTERNAL_URL', 'http://rails:3000'),
          auth_headers: auth_headers,
          cookie: raw_cookie
        )
        profile = client.profile
        raise Nex::Unauthorized if profile['id'].nil?

        {
          user_id: profile['id'],
          name: profile['name'] || profile['available_name'],
          email: profile['email'],
          accounts: Array(profile['accounts']),
          client: client,
          profile: profile
        }
      end
    end

    def account!(account_id)
      account = session[:accounts].find { |item| item['id'].to_i == account_id.to_i }
      raise Nex::Forbidden, 'Conta não autorizada' unless account

      account
    end

    def administrator?(account_id)
      account!(account_id)['role'].to_s == 'administrator'
    end

    private

    def auth_headers
      from_request = extract_headers
      return from_request if from_request['access-token']

      from_cookie
    end

    def extract_headers
      {
        'access-token' => header('HTTP_ACCESS_TOKEN'),
        'token-type' => header('HTTP_TOKEN_TYPE') || 'Bearer',
        'client' => header('HTTP_CLIENT'),
        'expiry' => header('HTTP_EXPIRY'),
        'uid' => header('HTTP_UID')
      }.compact
    end

    def from_cookie
      raw = cookie_value(COOKIE_NAME)
      return {} if raw.to_s.empty?

      data = JSON.parse(CGI.unescape(raw))
      {
        'access-token' => data['access-token'] || data['access_token'],
        'token-type' => data['token-type'] || 'Bearer',
        'client' => data['client'],
        'expiry' => data['expiry'],
        'uid' => data['uid']
      }.compact
    rescue JSON::ParserError
      {}
    end

    def cookie_value(name)
      jar = @env['HTTP_COOKIE'].to_s.split(';').map(&:strip)
      pair = jar.find { |item| item.start_with?("#{name}=") }
      return nil unless pair

      pair.split('=', 2)[1]
    end

    def raw_cookie
      @env['HTTP_COOKIE']
    end

    def header(key)
      value = @env[key]
      value.to_s.empty? ? nil : value
    end
  end
end
