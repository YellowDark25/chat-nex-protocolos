# frozen_string_literal: true

module Nex
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: 400)
      super(message)
      @status = status
    end
  end

  class Unauthorized < Error
    def initialize(message = 'Sessão do Chatwoot expirada')
      super(message, status: 401)
    end
  end

  class Forbidden < Error
    def initialize(message = 'Sem permissão')
      super(message, status: 403)
    end
  end

  class NotFound < Error
    def initialize(message = 'Não encontrado')
      super(message, status: 404)
    end
  end

  class Conflict < Error
    def initialize(message)
      super(message, status: 409)
    end
  end

  class Unavailable < Error
    def initialize(message = 'Chatwoot indisponível. Recarregue a página.')
      super(message, status: 503)
    end
  end
end
