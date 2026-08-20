# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'json'
require_relative 'lib/db'
require_relative 'lib/auth'
require_relative 'lib/errors'
require_relative 'lib/chamado_service'

module Nex
  class App < Sinatra::Base
    set :show_exceptions, false
    set :dump_errors, true
    set :host_authorization, permitted_hosts: []

    configure do
      db = Nex::Db.connect!
      Nex::Db.migrate!(db)
      set :db, db
    end

    helpers do
      def auth
        @auth ||= Nex::Auth.new(env)
      end

      def account_id
        value = params[:account_id] || env['HTTP_X_ACCOUNT_ID']
        raise Nex::Error, 'account_id obrigatório' if value.to_s.empty?

        value.to_i
      end

      def service
        auth.account!(account_id)
        Nex::ChamadoService.new(db: settings.db, session: auth.session, account_id: account_id)
      end

      def json_body
        raw = request.body.read
        return {} if raw.to_s.empty?

        JSON.parse(raw, symbolize_names: true)
      rescue JSON::ParserError
        raise Nex::Error, 'JSON inválido'
      end

      def json_request?
        request.media_type.to_s.include?('json')
      end

      def uploaded_files(*keys)
        keys.flat_map { |key| Array(params[key]) }.filter_map { |item| upload_hash(item) }
      end

      def upload_hash(item)
        return item if item.is_a?(Hash) && item[:tempfile]
        return unless item.respond_to?(:tempfile) && item.tempfile

        {
          tempfile: item.tempfile,
          filename: item.respond_to?(:original_filename) ? item.original_filename : 'audio.webm',
          type: item.respond_to?(:content_type) ? item.content_type : nil
        }
      end
    end

    before do
      content_type :json
    end

    get '/health' do
      json(ok: true)
    end

    get '/session' do
      session = auth.session
      json(
        user: { id: session[:user_id], name: session[:name], email: session[:email] },
        accounts: session[:accounts]
      )
    end

    get '/users' do
      json(items: service.list_users)
    end

    post '/transcribe' do
      json(service.transcribe_upload(uploaded_files(:file, :files, :'files[]').first))
    end

    get '/chamados' do
      json(service.list(params))
    end

    get '/chamados/by-conversation/:conversation_id' do
      json(items: service.by_conversation(params[:conversation_id]))
    end

    get '/chamados/:number' do
      json(service.show(params[:number]))
    end

    get '/chamados/:number/comments' do
      json(items: service.comments(params[:number]))
    end

    post '/chamados/:number/comments' do
      files = uploaded_files(:file, :files, :'files[]')
      text = json_request? ? json_body[:body] : params[:body]
      json(service.add_comment(params[:number], text, files: files))
    end

    post '/chamados' do
      json(service.create(json_body))
    end

    patch '/chamados/:number' do
      json(service.update(params[:number], json_body))
    end

    post '/chamados/:number/assume' do
      json(service.assume(params[:number]))
    end

    post '/chamados/:number/leave' do
      json(service.leave(params[:number], json_body[:reason]))
    end

    post '/chamados/:number/watch' do
      json(service.watch(params[:number]))
    end

    delete '/chamados/:number/watch' do
      json(service.unwatch(params[:number]))
    end

    post '/chamados/:number/conversations' do
      json(service.link_conversation(params[:number], json_body[:conversation_id] || json_body[:display_id]))
    end

    delete '/chamados/:number/conversations/:conversation_id' do
      json(service.unlink_conversation(params[:number], params[:conversation_id]))
    end

    post '/chamados/:number/contacts' do
      json(service.link_contact(params[:number], json_body[:contact_id]))
    end

    delete '/chamados/:number/contacts/:contact_id' do
      json(service.unlink_contact(params[:number], params[:contact_id]))
    end

    post '/chamados/:number/attachments' do
      json(service.attach(params[:number], params[:file]))
    end

    get '/chamados/:number/attachments/:id' do
      path, row = service.attachment_path(params[:number], params[:id])
      previewable = row[:content_type].to_s.start_with?('image/', 'audio/') || row[:content_type] == 'application/pdf'
      send_file(
        path,
        filename: row[:filename],
        type: row[:content_type],
        disposition: previewable ? 'inline' : 'attachment'
      )
    end

    post '/chamados/:number/restore' do
      json(service.restore(params[:number]))
    end

    delete '/chamados/:number' do
      json(service.destroy(params[:number]))
    end

    get '/search/conversations' do
      json(service.search_conversations(params[:q]))
    end

    get '/conversations/:conversation_id/contact-attributes' do
      json(service.contact_form_for_conversation(params[:conversation_id]))
    end

    post '/conversations/:conversation_id/mark-removed' do
      service.mark_conversation_removed(params[:conversation_id])
      json(ok: true)
    end

    error Nex::Error do
      error = env['sinatra.error']
      status error.status
      json(error: error.message, reload: error.is_a?(Nex::Unavailable) || error.is_a?(Nex::Unauthorized))
    end

    error do
      status 500
      json(error: 'Erro interno')
    end
  end
end
