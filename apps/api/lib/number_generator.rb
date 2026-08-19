# frozen_string_literal: true

module Nex
  class NumberGenerator
    PREFIX = 'CHAM'

    def initialize(db)
      @db = db
    end

    def next_number(account_id)
      year = Time.now.year
      @db.transaction do
        existing = @db[:nex_chamado_sequences].where(account_id: account_id, year: year).for_update.first
        if existing
          value = existing[:last_value].to_i + 1
          @db[:nex_chamado_sequences].where(account_id: account_id, year: year).update(last_value: value)
        else
          value = 1
          @db[:nex_chamado_sequences].insert(account_id: account_id, year: year, last_value: value)
        end
        format('%s-%d-%06d', PREFIX, year, value)
      end
    end
  end
end
