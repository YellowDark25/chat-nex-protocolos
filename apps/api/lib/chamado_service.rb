# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'securerandom'
require_relative 'errors'
require_relative 'groq_client'
require_relative 'number_generator'

module Nex
  class ChamadoService
    OPEN_STATUSES = %w[pendente em_atendimento].freeze
    CLOSED_STATUSES = %w[resolvido cancelado].freeze
    ALL_STATUSES = (OPEN_STATUSES + CLOSED_STATUSES).freeze
    ALL_PRIORITIES = %w[baixa media alta].freeze
    PAGE_SIZES = [10, 25, 50, 100].freeze
    DEFAULT_PAGE_SIZE = 10
    SUBJECT_MAX = 255
    ASSUNTO_MAX = 2000
    COMMENT_MAX = 4000
    COMMENT_IMAGES_MAX = 5
    COMMENT_AUDIOS_MAX = 1
    IMAGE_MAX_BYTES = 8 * 1024 * 1024
    AUDIO_MAX_BYTES = 10 * 1024 * 1024
    IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
    AUDIO_TYPES = %w[audio/webm audio/ogg audio/mp4 audio/mpeg audio/wav audio/x-wav audio/aac audio/x-m4a].freeze
    UPLOAD_ROOT = ENV.fetch('UPLOAD_DIR', '/data/uploads')

    def initialize(db:, session:, account_id:)
      @db = db
      @session = session
      @account_id = account_id.to_i
      @user_id = session[:user_id]
      @client = session[:client]
    end

    def list(params)
      page_size = PAGE_SIZES.include?(params[:per_page].to_i) ? params[:per_page].to_i : DEFAULT_PAGE_SIZE
      page = [params[:page].to_i, 1].max
      scope = list_scope(params)
      scope = apply_user_filter(scope, params[:user_id]) unless params[:user_id].to_s == 'todos'
      scope = apply_status_filter(scope, params[:status])
      scope = apply_priority_filter(scope, params[:priority])
      scope = apply_search(scope, params[:q])
      scope = apply_sort(scope, params[:sort])
      total = scope.count
      rows = scope.limit(page_size).offset((page - 1) * page_size).all
      {
        items: rows.map { |row| serialize_list_item(row) },
        page: page,
        per_page: page_size,
        total: total
      }
    end

    def list_users
      Array(agents_payload)
        .select { |agent| agent.is_a?(Hash) && agent['confirmed'] != false }
        .map { |agent| serialize_account_user(agent) }
        .sort_by { |user| user[:name].to_s.downcase }
    end

    def show(number)
      serialize_detail(find_for_read!(number))
    end

    def comments(number)
      protocolo = find_for_read!(number)
      rows = @db[:nex_chamado_comments].where(chamado_id: protocolo[:id]).order(:created_at).all
      files_by_comment = comment_files_of(rows.map { |row| row[:id] })
      rows.map { |row| serialize_comment(row, **split_comment_media(files_by_comment[row[:id]] || [])) }
    end

    def add_comment(number, body, files: [])
      files = Array(files).compact
      text = assert_comment!(body, allow_empty: !files.empty?)
      assert_comment_files!(files)
      protocolo = find_by_number!(number)
      comment_id = @db[:nex_chamado_comments].insert(
        chamado_id: protocolo[:id],
        user_id: @user_id,
        body: text,
        created_at: Time.now
      )
      files.each { |file| persist_upload(protocolo, file, comment_id: comment_id) }
      serialize_comment(
        @db[:nex_chamado_comments].where(id: comment_id).first,
        **split_comment_media(comment_files_of([comment_id])[comment_id] || [])
      )
    end

    def contact_form_for_conversation(display_id)
      conversation = fetch_conversation(display_id)
      sender = conversation.dig('meta', 'sender') || {}
      values = sender['custom_attributes'] || {}
      definitions = Array(@client.custom_attribute_definitions(@account_id, 'contact_attribute'))
      {
        contact_id: sender['id'],
        contact_name: sender['name'],
        attributes: definitions.map { |definition| serialize_contact_attribute(definition, values) }
      }
    end

    def by_conversation(conversation_id)
      links = @db[:nex_chamado_conversations]
              .where(conversation_id: conversation_id.to_i, removed_at: nil)
              .select_map(:chamado_id)
      return [] if links.empty?

      visible_chamados
        .where(id: links)
        .order(Sequel.desc(:updated_at))
        .all
        .map { |row| serialize_list_item(row) }
        .sort_by { |item| OPEN_STATUSES.include?(item[:status]) ? 0 : 1 }
    end

    def create(payload)
      display_id = payload[:conversation_display_id] || payload[:conversation_id]
      raise Nex::Error, 'Conversa obrigatória' if display_id.to_s.empty?
      assunto = assert_assunto!(payload[:assunto])
      raise Nex::Error, 'Resumo deve ter no máximo 255 caracteres' if payload[:subject].to_s.length > SUBJECT_MAX

      conversation = fetch_conversation(display_id)
      persist_contact_attributes(conversation, payload[:contact_attributes])
      conversation_pk = conversation_pk_from(conversation)
      contact_id = contact_id_from(conversation)
      number = nil
      chamado_id = nil
      now = Time.now
      @db.transaction do
        lock_conversation(conversation_pk)
        number = NumberGenerator.new(@db).next_number(@account_id)
        chamado_id = @db[:nex_chamados].insert(
          account_id: @account_id,
          number: number,
          subject: blank_to_nil(payload[:subject]),
          assunto: assunto,
          status: 'em_atendimento',
          priority: blank_to_nil(payload[:priority]),
          due_on: blank_to_nil(payload[:due_on]),
          opened_by_user_id: @user_id,
          opened_from_conversation_id: conversation_pk,
          opened_at: now,
          created_at: now,
          updated_at: now
        )
        @db[:nex_chamado_conversations].insert(
          chamado_id: chamado_id,
          conversation_id: conversation_pk,
          display_id: conversation['id'] || display_id.to_i,
          label: conversation_label(conversation),
          is_origin: true,
          created_at: now
        )
        attach_contact(chamado_id, contact_id)
        add_participante(chamado_id, @user_id)
        record_event(chamado_id, 'chamado_aberto', {
          conversation_id: conversation_pk,
          display_id: conversation['id'],
          contact_id: contact_id,
          notify: payload[:notify],
          assunto: assunto
        })
      end

      deliver_opening_message(conversation, number, payload)
      assign_origin_if_needed(conversation, display_id)
      find_and_serialize(chamado_id)
    end

    def update(number, payload)
      protocolo = find_by_number!(number)
      values = {}
      values[:subject] = payload[:subject] if payload.key?(:subject)
      values[:assunto] = assert_assunto!(payload[:assunto]) if payload.key?(:assunto)
      values[:priority] = payload[:priority] if payload.key?(:priority)
      values[:due_on] = payload[:due_on] if payload.key?(:due_on)
      apply_status_change(protocolo, payload[:status], payload[:reason]) if payload[:status]
      touch(protocolo[:id], values) unless values.empty?
      serialize_detail(find_by_number!(number))
    end

    def assume(number)
      protocolo = find_by_number!(number)
      add_participante(protocolo[:id], @user_id)
      record_event(protocolo[:id], 'assumiu', { user_id: @user_id })
      assign_origin_conversation(protocolo)
      notify(protocolo, "Você foi adicionado ao chamado #{protocolo[:number]}")
      touch(protocolo[:id], status: protocolo[:status] == 'pendente' ? 'em_atendimento' : protocolo[:status])
      serialize_detail(find_by_number!(number))
    end

    def leave(number, reason)
      raise Nex::Error, 'Motivo obrigatório para largar' if reason.to_s.strip.empty?

      protocolo = find_by_number!(number)
      @db[:nex_chamado_participantes].where(chamado_id: protocolo[:id], user_id: @user_id).delete
      remaining = @db[:nex_chamado_participantes].where(chamado_id: protocolo[:id]).count
      values = {}
      values[:status] = 'pendente' if remaining.zero? && OPEN_STATUSES.include?(protocolo[:status])
      record_event(protocolo[:id], 'largou', { reason: reason, remaining: remaining })
      touch(protocolo[:id], values)
      serialize_detail(find_by_number!(number))
    end

    def watch(number)
      protocolo = find_by_number!(number)
      @db[:nex_chamado_watchers].insert_conflict(target: %i[chamado_id user_id]).insert(
        chamado_id: protocolo[:id], user_id: @user_id, created_at: Time.now
      )
      record_event(protocolo[:id], 'observando', { user_id: @user_id })
      serialize_detail(find_by_number!(number))
    end

    def unwatch(number)
      protocolo = find_by_number!(number)
      @db[:nex_chamado_watchers].where(chamado_id: protocolo[:id], user_id: @user_id).delete
      record_event(protocolo[:id], 'parou_observar', { user_id: @user_id })
      serialize_detail(find_by_number!(number))
    end

    def link_conversation(number, display_id)
      protocolo = find_by_number!(number)
      conversation = fetch_conversation(display_id)
      conversation_pk = conversation_pk_from(conversation)
      @db[:nex_chamado_conversations].insert_conflict(target: %i[chamado_id conversation_id]).insert(
        chamado_id: protocolo[:id],
        conversation_id: conversation_pk,
        display_id: conversation['id'] || display_id.to_i,
        label: conversation_label(conversation),
        is_origin: false,
        created_at: Time.now
      )
      attach_contact(protocolo[:id], contact_id_from(conversation))
      record_event(protocolo[:id], 'conversa_vinculada', { display_id: conversation['id'] })
      notify(protocolo, "Conversa ##{conversation['id']} vinculada ao chamado #{protocolo[:number]}")
      touch(protocolo[:id])
      serialize_detail(find_by_number!(number))
    end

    def unlink_conversation(number, conversation_id)
      protocolo = find_by_number!(number)
      link = @db[:nex_chamado_conversations].where(
        chamado_id: protocolo[:id], conversation_id: conversation_id.to_i, removed_at: nil
      ).first
      raise Nex::NotFound, 'Vínculo não encontrado' unless link

      remaining = @db[:nex_chamado_conversations].where(chamado_id: protocolo[:id], removed_at: nil).count
      if link[:is_origin] && remaining <= 1
        raise Nex::Error, 'A conversa de origem só sai se sobrar outra'
      end

      @db[:nex_chamado_conversations].where(id: link[:id]).update(removed_at: Time.now)
      record_event(protocolo[:id], 'conversa_desvinculada', { conversation_id: conversation_id })
      touch(protocolo[:id])
      serialize_detail(find_by_number!(number))
    end

    def link_contact(number, contact_id)
      raise Nex::Error, 'Contato obrigatório' if contact_id.to_i.zero?

      protocolo = find_by_number!(number)
      attach_contact(protocolo[:id], contact_id)
      record_event(protocolo[:id], 'contato_vinculado', { contact_id: contact_id.to_i })
      touch(protocolo[:id])
      serialize_detail(find_by_number!(number))
    end

    def unlink_contact(number, contact_id)
      protocolo = find_by_number!(number)
      @db[:nex_chamado_contacts].where(chamado_id: protocolo[:id], contact_id: contact_id.to_i).delete
      record_event(protocolo[:id], 'contato_desvinculado', { contact_id: contact_id })
      touch(protocolo[:id])
      serialize_detail(find_by_number!(number))
    end

    def attach(number, file)
      raise Nex::Error, 'Arquivo obrigatório' unless file

      protocolo = find_by_number!(number)
      persist_upload(protocolo, file)
      record_event(protocolo[:id], 'anexo', { filename: file[:filename] })
      touch(protocolo[:id])
      serialize_detail(find_by_number!(number))
    end

    def attachment_path(number, attachment_id)
      protocolo = find_for_read!(number)
      row = @db[:nex_chamado_attachments].where(id: attachment_id, chamado_id: protocolo[:id]).first
      raise Nex::NotFound unless row

      [File.join(UPLOAD_ROOT, row[:storage_key]), row]
    end

    def destroy(number)
      raise Nex::Forbidden, 'Só administrator apaga' unless administrator?

      protocolo = find_by_number!(number)
      now = Time.now
      @db[:nex_chamados].where(id: protocolo[:id]).update(
        deleted_at: now,
        deleted_by_user_id: @user_id,
        updated_at: now
      )
      record_event(protocolo[:id], 'apagou', {})
      { deleted: true, number: number }
    end

    def restore(number)
      raise Nex::Forbidden, 'Só administrator restaura' unless administrator?

      protocolo = find_by_number!(number, include_deleted: true)
      raise Nex::Error, 'Chamado não está na lixeira' unless protocolo[:deleted_at]

      touch(protocolo[:id], deleted_at: nil, deleted_by_user_id: nil)
      record_event(protocolo[:id], 'restaurou', {})
      serialize_detail(find_by_number!(number))
    end

    def search_conversations(query)
      raise Nex::Error, 'Busca vazia' if query.to_s.strip.empty?

      payload = @client.search_conversations(@account_id, query)
      payload
    end

    def mark_conversation_removed(conversation_id)
      @db[:nex_chamado_conversations]
        .where(conversation_id: conversation_id.to_i, removed_at: nil)
        .update(removed_at: Time.now)
    end

    private

    def account_chamados
      @db[:nex_chamados].where(account_id: @account_id)
    end

    def visible_chamados
      account_chamados.where(deleted_at: nil)
    end

    def list_scope(params)
      if trashed_param?(params)
        raise Nex::Forbidden, 'Só administrator vê a lixeira' unless administrator?

        return account_chamados.exclude(deleted_at: nil)
      end

      visible_chamados
    end

    def trashed_param?(params)
      %w[1 true].include?(params[:trashed].to_s.downcase)
    end

    def find_by_number!(number, include_deleted: false)
      scope = include_deleted ? account_chamados : visible_chamados
      row = scope.where(number: number).first
      raise Nex::NotFound, 'Chamado não encontrado' unless row

      row
    end

    def find_for_read!(number)
      find_by_number!(number, include_deleted: administrator?)
    end

    def find_and_serialize(id)
      serialize_detail(@db[:nex_chamados].where(id: id).first)
    end

    def apply_user_filter(scope, user_id)
      uid = user_id.to_i.zero? ? @user_id : user_id.to_i
      chamado_ids = (
        account_chamados.where(opened_by_user_id: uid).select_map(:id) +
        @db[:nex_chamado_participantes].where(user_id: uid).select_map(:chamado_id) +
        @db[:nex_chamado_watchers].where(user_id: uid).select_map(:chamado_id)
      ).uniq
      scope.where(id: chamado_ids.empty? ? [0] : chamado_ids)
    end

    def agents_payload
      payload = @client.agents(@account_id)
      return payload['payload'] if payload.is_a?(Hash) && payload['payload']

      payload
    rescue Nex::Error
      []
    end

    def serialize_account_user(agent)
      name = agent['name'].to_s.strip
      name = agent['available_name'].to_s.strip if name.empty?
      name = agent['email'].to_s if name.empty?
      { id: agent['id'], name: name, email: agent['email'] }
    end

    def apply_status_filter(scope, status_param)
      statuses = Array(status_param).flat_map { |item| item.to_s.split(',') }.reject(&:empty?)
      return scope if statuses.empty?

      invalid = statuses - ALL_STATUSES
      raise Nex::Error, 'Status inválido' unless invalid.empty?

      scope.where(status: statuses)
    end

    def apply_priority_filter(scope, priority_param)
      priorities = Array(priority_param).flat_map { |item| item.to_s.split(',') }.reject(&:empty?)
      return scope if priorities.empty?

      invalid = priorities - ALL_PRIORITIES
      raise Nex::Error, 'Prioridade inválida' unless invalid.empty?

      scope.where(priority: priorities)
    end

    def apply_search(scope, query)
      term = query.to_s.strip
      return scope if term.empty?

      scope.where(
        Sequel.ilike(:number, "%#{term}%") |
          Sequel.ilike(Sequel.function(:coalesce, :subject, ''), "%#{term}%") |
          Sequel.ilike(Sequel.function(:coalesce, :assunto, ''), "%#{term}%")
      )
    end

    def apply_sort(scope, sort)
      case sort.to_s
      when 'number'
        scope.order(Sequel.desc(:number))
      when 'status'
        scope.order(:status, Sequel.desc(:updated_at))
      else
        scope.order(Sequel.desc(:updated_at))
      end
    end

    def apply_status_change(protocolo, status, reason)
      raise Nex::Error, 'Status inválido' unless ALL_STATUSES.include?(status)
      if status == 'cancelado' && reason.to_s.strip.empty?
        raise Nex::Error, 'Motivo obrigatório'
      end
      return if protocolo[:status] == status

      now = Time.now
      values = { status: status }
      payload = { from: protocolo[:status], to: status, reason: reason }

      if closing_status?(protocolo[:status], status)
        seconds = open_seconds_since(protocolo, now)
        payload[:open_seconds] = seconds
        values[:last_open_seconds] = seconds
      elsif reopening_status?(protocolo[:status], status)
        values[:opened_at] = now
      end

      record_event(protocolo[:id], 'status', payload)
      notify(protocolo, "Chamado #{protocolo[:number]} agora está #{status}")
      touch(protocolo[:id], values)
    end

    def closing_status?(from, to)
      OPEN_STATUSES.include?(from) && CLOSED_STATUSES.include?(to)
    end

    def reopening_status?(from, to)
      CLOSED_STATUSES.include?(from) && OPEN_STATUSES.include?(to)
    end

    def open_seconds_since(protocolo, now)
      started = protocolo[:opened_at] || protocolo[:created_at]
      return 0 unless started

      [(now - started).to_i, 0].max
    end

    def add_participante(chamado_id, user_id)
      @db[:nex_chamado_participantes].insert_conflict(target: %i[chamado_id user_id]).insert(
        chamado_id: chamado_id, user_id: user_id, created_at: Time.now
      )
    end

    def record_event(chamado_id, event_type, payload)
      @db[:nex_chamado_events].insert(
        chamado_id: chamado_id,
        event_type: event_type,
        actor_user_id: @user_id,
        payload: Sequel.pg_jsonb(payload),
        created_at: Time.now
      )
    end

    def touch(chamado_id, extra = {})
      @db[:nex_chamados].where(id: chamado_id).update(extra.merge(updated_at: Time.now))
    end

    def fetch_conversation(display_id)
      @client.conversation(@account_id, display_id)
    end

    def serialize_contact_attribute(definition, values)
      key = definition['attribute_key']
      {
        key: key,
        label: definition['attribute_display_name'],
        type: definition['attribute_display_type'],
        description: definition['attribute_description'],
        options: Array(definition['attribute_values']),
        value: values[key]
      }
    end

    def contact_id_from(conversation)
      conversation.dig('meta', 'sender', 'id') || conversation.dig('contact', 'id')
    end

    def attach_contact(chamado_id, contact_id)
      return if contact_id.to_i.zero?

      @db[:nex_chamado_contacts].insert_conflict(target: %i[chamado_id contact_id]).insert(
        chamado_id: chamado_id, contact_id: contact_id.to_i, created_at: Time.now
      )
    end

    def persist_contact_attributes(conversation, attrs)
      return if attrs.nil? || attrs.empty?

      contact_id = contact_id_from(conversation)
      return unless contact_id

      payload = attrs.each_with_object({}) do |(key, value), memo|
        next if value.nil?

        memo[key.to_s] = value
      end
      return if payload.empty?

      @client.update_contact(@account_id, contact_id, custom_attributes: payload)
    end

    def conversation_pk_from(conversation)
      conversation['id'].to_i
    end

    def conversation_unassigned?(conversation)
      conversation.dig('meta', 'assignee').nil?
    end

    def lock_conversation(conversation_id)
      @db.run("SELECT pg_advisory_xact_lock(#{conversation_id.to_i})")
    end

    def deliver_opening_message(conversation, number, payload)
      display_id = conversation['id']
      case payload[:notify].to_s
      when 'chat'
        @client.create_message(@account_id, display_id, content: "Seu chamado é #{number}", private_note: false)
      when 'note'
        subject = payload[:subject].to_s
        assunto = payload[:assunto].to_s
        text = [
          "Chamado #{number}",
          (subject.empty? ? nil : "Resumo: #{subject}"),
          (assunto.empty? ? nil : "Assunto: #{assunto}"),
          "Abrir: /chamados/#{number}"
        ].compact.join("\n")
        @client.create_message(@account_id, display_id, content: text, private_note: true)
      end
    rescue Nex::Error
      nil
    end

    def assign_origin_if_needed(conversation, display_id)
      return unless conversation_unassigned?(conversation)

      @client.assign_conversation(@account_id, display_id, @user_id)
    rescue Nex::Error
      nil
    end

    def assign_origin_conversation(protocolo)
      origin = @db[:nex_chamado_conversations].where(chamado_id: protocolo[:id], is_origin: true).first
      return unless origin

      @client.assign_conversation(@account_id, origin[:display_id], @user_id)
    rescue Nex::Error
      nil
    end

    def notify(protocolo, text)
      origin = @db[:nex_chamado_conversations].where(chamado_id: protocolo[:id], is_origin: true).first
      return unless origin

      @client.create_message(@account_id, origin[:display_id], content: text, private_note: true)
    rescue Nex::Error
      nil
    end

    def administrator?
      account = @session[:accounts].find { |item| item['id'].to_i == @account_id }
      account && account['role'].to_s == 'administrator'
    end

    def serialize_list_item(row)
      {
        id: row[:id],
        number: row[:number],
        subject: row[:subject],
        assunto: row[:assunto],
        status: row[:status],
        priority: row[:priority],
        due_on: row[:due_on],
        opened_by_user_id: row[:opened_by_user_id],
        opened_by: serialize_member(row[:opened_by_user_id]),
        participantes: serialize_members(participantes_of(row[:id])),
        watchers: serialize_members(watchers_of(row[:id])),
        conversations: conversations_of(row[:id]),
        opened_at: row[:opened_at],
        last_open_seconds: row[:last_open_seconds],
        deleted_at: row[:deleted_at],
        updated_at: row[:updated_at],
        created_at: row[:created_at]
      }
    end

    def serialize_detail(row)
      serialize_list_item(row).merge(
        opened_from_conversation_id: row[:opened_from_conversation_id],
        contacts: contacts_of(row[:id]),
        attachments: @db[:nex_chamado_attachments]
          .where(chamado_id: row[:id], comment_id: nil)
          .order(:created_at)
          .all
          .map { |file| serialize_attachment(file) },
        events: @db[:nex_chamado_events].where(chamado_id: row[:id]).order(Sequel.desc(:created_at)).all.map do |event|
          {
            id: event[:id],
            type: event[:event_type],
            actor: serialize_member(event[:actor_user_id]),
            actor_user_id: event[:actor_user_id],
            payload: event[:payload],
            created_at: event[:created_at]
          }
        end
      )
    end

    def participantes_of(chamado_id)
      @db[:nex_chamado_participantes].where(chamado_id: chamado_id).select_map(:user_id)
    end

    def watchers_of(chamado_id)
      @db[:nex_chamado_watchers].where(chamado_id: chamado_id).select_map(:user_id)
    end

    def serialize_members(user_ids)
      user_ids.map { |user_id| serialize_member(user_id) }
    end

    def serialize_member(user_id)
      return { id: nil, name: nil, email: nil } if user_id.to_i.zero?

      user_directory[user_id.to_i] || { id: user_id.to_i, name: "##{user_id}", email: nil }
    end

    def user_directory
      @user_directory ||= begin
        directory = Array(agents_payload).each_with_object({}) do |agent, memo|
          next unless agent.is_a?(Hash)

          memo[agent['id'].to_i] = serialize_account_user(agent)
        end
        directory[@user_id.to_i] ||= {
          id: @user_id.to_i,
          name: @session[:name],
          email: @session[:email]
        }
        directory
      end
    end

    def contacts_of(chamado_id)
      @db[:nex_chamado_contacts].where(chamado_id: chamado_id).order(:created_at).select_map(:contact_id).map do |contact_id|
        serialize_linked_contact(contact_id)
      end
    end

    def serialize_linked_contact(contact_id)
      payload = @client.contact(@account_id, contact_id)
      data = payload['payload'] || payload
      name = data['name'].to_s.strip
      { id: contact_id, name: name.empty? ? nil : name }
    rescue Nex::Error
      { id: contact_id, name: nil }
    end

    def conversations_of(chamado_id)
      @db[:nex_chamado_conversations].where(chamado_id: chamado_id).order(:created_at).all.map do |link|
        {
          conversation_id: link[:conversation_id],
          display_id: link[:display_id],
          label: filled_conversation_label(link),
          is_origin: link[:is_origin],
          removed: !link[:removed_at].nil?
        }
      end
    end

    def conversation_label(conversation)
      sender = conversation.dig('meta', 'sender') || conversation['contact'] || {}
      name = sender['name'].to_s.strip
      name.empty? ? nil : name
    end

    def filled_conversation_label(link)
      stored = link[:label].to_s.strip
      return stored unless stored.empty?
      return if link[:removed_at] || link[:display_id].to_i.zero?

      name = conversation_label(fetch_conversation(link[:display_id]))
      return if name.to_s.empty?

      @db[:nex_chamado_conversations].where(id: link[:id]).update(label: name)
      name
    rescue Nex::Error
      nil
    end

    def persist_upload(protocolo, file, comment_id: nil)
      raise Nex::Error, 'Arquivo obrigatório' unless file && file[:tempfile]

      FileUtils.mkdir_p(UPLOAD_ROOT)
      key = "#{protocolo[:id]}/#{SecureRandom.hex(8)}-#{File.basename(file[:filename].to_s)}"
      path = File.join(UPLOAD_ROOT, key)
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(file[:tempfile].path, path)
      content_type = media_type(file)
      attachment_id = @db[:nex_chamado_attachments].insert(
        chamado_id: protocolo[:id],
        comment_id: comment_id,
        filename: file[:filename],
        content_type: content_type,
        byte_size: File.size(path),
        storage_key: key,
        uploaded_by_user_id: @user_id,
        created_at: Time.now
      )
      attach_audio_transcript(attachment_id, path, content_type, file[:filename])
      attachment_id
    end

    def attach_audio_transcript(attachment_id, path, content_type, filename)
      return unless GroqClient.enabled?
      return unless content_type.to_s.start_with?('audio/')

      text = GroqClient.new.transcribe(path: path, filename: filename, content_type: content_type)
      return if text.to_s.strip.empty?

      @db[:nex_chamado_attachments].where(id: attachment_id).update(transcript: text)
    end

    def comment_files_of(comment_ids)
      return {} if comment_ids.empty?

      @db[:nex_chamado_attachments]
        .where(comment_id: comment_ids)
        .order(:created_at)
        .all
        .group_by { |file| file[:comment_id] }
        .transform_values { |files| files.map { |file| serialize_attachment(file) } }
    end

    def split_comment_media(files)
      {
        images: files.select { |file| file[:content_type].to_s.start_with?('image/') },
        audios: files.select { |file| file[:content_type].to_s.start_with?('audio/') }
      }
    end

    def media_type(file)
      type = file[:type].to_s.split(';').first.to_s.strip
      return type unless type.empty?

      name = file[:filename].to_s.downcase
      return 'audio/webm' if name.end_with?('.webm')
      return 'audio/mp4' if name.end_with?('.m4a', '.mp4')
      return 'audio/ogg' if name.end_with?('.ogg')
      return 'audio/mpeg' if name.end_with?('.mp3')
      return 'audio/wav' if name.end_with?('.wav')

      type
    end

    def serialize_attachment(file)
      {
        id: file[:id],
        filename: file[:filename],
        content_type: file[:content_type],
        byte_size: file[:byte_size],
        transcript: file[:transcript],
        created_at: file[:created_at]
      }
    end

    def serialize_comment(row, images: [], audios: [])
      {
        id: row[:id],
        body: row[:body],
        created_at: row[:created_at],
        author: serialize_member(row[:user_id]),
        images: images,
        audios: audios
      }
    end

    def assert_comment!(value, allow_empty: false)
      text = value.to_s.strip
      raise Nex::Error, 'Mensagem, imagem ou áudio obrigatório' if text.empty? && !allow_empty
      raise Nex::Error, "Mensagem deve ter no máximo #{COMMENT_MAX} caracteres" if text.length > COMMENT_MAX

      text
    end

    def assert_comment_files!(files)
      images = files.select { |file| IMAGE_TYPES.include?(media_type(file)) }
      audios = files.select { |file| AUDIO_TYPES.include?(media_type(file)) }
      raise Nex::Error, "No máximo #{COMMENT_IMAGES_MAX} imagens por comentário" if images.length > COMMENT_IMAGES_MAX
      raise Nex::Error, "No máximo #{COMMENT_AUDIOS_MAX} áudio por comentário" if audios.length > COMMENT_AUDIOS_MAX
      raise Nex::Error, 'Só imagens (JPEG, PNG, GIF ou WebP) ou áudio' if images.length + audios.length != files.length

      images.each do |file|
        raise Nex::Error, 'Imagem deve ter no máximo 8 MB' if File.size(file[:tempfile].path) > IMAGE_MAX_BYTES
      end
      audios.each do |file|
        raise Nex::Error, 'Áudio deve ter no máximo 10 MB' if File.size(file[:tempfile].path) > AUDIO_MAX_BYTES
      end
    end

    def assert_assunto!(value)
      assunto = value.to_s.strip
      raise Nex::Error, 'Assunto obrigatório' if assunto.empty?
      raise Nex::Error, "Assunto deve ter no máximo #{ASSUNTO_MAX} caracteres" if assunto.length > ASSUNTO_MAX

      assunto
    end

    def blank_to_nil(value)
      value.to_s.strip.empty? ? nil : value
    end
  end
end
