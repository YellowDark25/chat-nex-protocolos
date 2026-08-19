# frozen_string_literal: true

require 'faraday'
require 'json'
require_relative 'errors'

module Nex
  class ChatwootClient
    AUTH_HEADER_KEYS = %w[access-token token-type client expiry uid].freeze

    def initialize(base_url:, auth_headers:, cookie: nil)
      @base_url = base_url.chomp('/')
      @auth_headers = auth_headers
      @cookie = cookie
    end

    def profile
      get('/api/v1/profile')
    end

    def agents(account_id)
      get("/api/v1/accounts/#{account_id}/agents")
    end

    def conversation(account_id, display_id)
      get("/api/v1/accounts/#{account_id}/conversations/#{display_id}")
    end

    def contact(account_id, contact_id)
      get("/api/v1/accounts/#{account_id}/contacts/#{contact_id}")
    end

    def search_conversations(account_id, query)
      get("/api/v1/accounts/#{account_id}/search", q: query)
    end

    def assign_conversation(account_id, display_id, assignee_id)
      post(
        "/api/v1/accounts/#{account_id}/conversations/#{display_id}/assignments",
        assignee_id: assignee_id
      )
    end

    def create_message(account_id, display_id, content:, private_note: false)
      post(
        "/api/v1/accounts/#{account_id}/conversations/#{display_id}/messages",
        content: content,
        private: private_note,
        message_type: 'outgoing'
      )
    end

    def custom_attribute_definitions(account_id, attribute_model)
      get(
        "/api/v1/accounts/#{account_id}/custom_attribute_definitions",
        attribute_model: attribute_model
      )
    end

    def update_contact(account_id, contact_id, custom_attributes:)
      put(
        "/api/v1/accounts/#{account_id}/contacts/#{contact_id}",
        custom_attributes: custom_attributes
      )
    end

    private

    def get(path, params = {})
      request(:get, path, params: params)
    end

    def post(path, body)
      request(:post, path, body: body)
    end

    def put(path, body)
      request(:put, path, body: body)
    end

    def request(method, path, params: nil, body: nil)
      response = connection.public_send(method, path) do |req|
        req.params.update(params) if params
        req.body = JSON.generate(body) if body
      end
      parse(response)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
      raise Nex::Unavailable, error.message
    end

    def parse(response)
      payload = response.body.to_s.empty? ? {} : JSON.parse(response.body)
      return payload if response.success?

      raise Nex::Unauthorized if [401, 403].include?(response.status)
      raise Nex::Unavailable if response.status >= 500
      raise Nex::Error.new(payload['message'] || 'Falha no Chatwoot', status: response.status)
    end

    def connection
      @connection ||= Faraday.new(url: @base_url) do |faraday|
        faraday.options.timeout = 8
        faraday.options.open_timeout = 4
        faraday.headers['Content-Type'] = 'application/json'
        faraday.headers['Accept'] = 'application/json'
        AUTH_HEADER_KEYS.each do |key|
          value = @auth_headers[key]
          faraday.headers[key] = value if value
        end
        faraday.headers['Cookie'] = @cookie if @cookie.to_s != ''
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
