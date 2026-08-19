# frozen_string_literal: true

require 'faraday'
require 'faraday/multipart'
require 'json'

module Nex
  class GroqClient
    BASE_URL = 'https://api.groq.com'
    TRANSCRIBE_PATH = '/openai/v1/audio/transcriptions'
    MODEL = 'whisper-large-v3-turbo'
    LANGUAGE = 'pt'
    TIMEOUT = 20
    OPEN_TIMEOUT = 5

    def self.enabled?
      !ENV.fetch('GROQ_API_KEY', '').strip.empty?
    end

    def transcribe(path:, filename:, content_type:)
      return unless self.class.enabled?

      response = connection.post(TRANSCRIBE_PATH) do |req|
        req.body = {
          file: Faraday::Multipart::FilePart.new(path, content_type, filename),
          model: MODEL,
          language: LANGUAGE
        }
      end
      parse_text(response)
    rescue Faraday::Error, JSON::ParserError => error
      warn("[groq] transcrição falhou: #{error.message}")
      nil
    end

    private

    def parse_text(response)
      unless response.success?
        warn("[groq] transcrição HTTP #{response.status}")
        return
      end

      text = JSON.parse(response.body)['text'].to_s.strip
      text.empty? ? nil : text
    end

    def connection
      Faraday.new(url: BASE_URL) do |faraday|
        faraday.request :multipart
        faraday.options.timeout = TIMEOUT
        faraday.options.open_timeout = OPEN_TIMEOUT
        faraday.headers['Authorization'] = "Bearer #{ENV.fetch('GROQ_API_KEY')}"
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
