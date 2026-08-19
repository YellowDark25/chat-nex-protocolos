# frozen_string_literal: true

require_relative 'app'

map ENV.fetch('API_SCRIPT_NAME', '/chamados-api') do
  run Nex::App
end
