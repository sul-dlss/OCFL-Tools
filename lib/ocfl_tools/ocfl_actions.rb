module OcflTools
  # Class for collating manifest actions, both for delta reporting and staging new versions.
  class OcflActions
    def initialize
      @my_actions                = {}
      @my_actions['add']         = {}
      @my_actions['update']      = {}
      @my_actions['copy']        = {}
      @my_actions['move']        = {}
      @my_actions['delete']      = {}
    end

    # Convenience method for obtaining a hash of recorded actions.
    # @return [Hash] of actions stored in this instance.
    def actions
      @my_actions
    end

    # Convenience method for obtaining a hash recorded of actions.
    # @return [Hash] of actions stored in this instance.
    def all
      @my_actions
    end

    def add(digest, filepath)
      if @my_actions['add'].key?(digest) == false
        @my_actions['add'][digest] = []
      end
      # Only put unique values into filepaths
      if @my_actions['add'][digest].include?(filepath)
          return @my_actions['add'][digest]
        else
          @my_actions['add'][digest] = ( @my_actions['add'][digest] << filepath )
      end
    end

    def update(digest, filepath)
      if @my_actions['update'].key?(digest) == false
        @my_actions['update'][digest] = []
      end
      # Only put unique values into filepaths
      if @my_actions['update'][digest].include?(filepath)
          return @my_actions['update'][digest]
        else
          @my_actions['update'][digest] = ( @my_actions['update'][digest] << filepath )
      end
    end

    def copy(digest, filepath)
      if @my_actions['copy'].key?(digest) == false
        @my_actions['copy'][digest] = []
      end
      # Only put unique values into filepaths
      if @my_actions['copy'][digest].include?(filepath)
          return @my_actions['copy'][digest]
        else
          @my_actions['copy'][digest] = ( @my_actions['copy'][digest] << filepath )
      end
    end

    def move(digest, filepath)
      if @my_actions['move'].key?(digest) == false
        @my_actions['move'][digest] = []
      end
      # Only put unique values into filepaths
      if @my_actions['move'][digest].include?(filepath)
          return @my_actions['move'][digest]
        else
          @my_actions['move'][digest] = ( @my_actions['move'][digest] << filepath )
      end
    end

    def delete(digest, filepath)
      if @my_actions['delete'].key?(digest) == false
        @my_actions['delete'][digest] = []
      end
      # Only put unique values into filepaths
      if @my_actions['delete'][digest].include?(filepath)
          return @my_actions['delete'][digest]
        else
          @my_actions['delete'][digest] = ( @my_actions['delete'][digest] << filepath )
      end
    end

    def fixity(digest, fixity_algorithm, fixity_digest)
      # Only create this key if used.
      if @my_actions.key?('fixity') == false
        @my_actions['fixity'] = {}
      end
      if @my_actions['fixity'].key?(fixity_algorithm) == false
        @my_actions['fixity'][fixity_algorithm] = {}
      end
      # only add unique fixity digests.
      if @my_actions['fixity'][fixity_algorithm].include?(digest)
          return @my_actions['fixity'][fixity_algorithm][digest]
        else
          @my_actions['fixity'][fixity_algorithm][digest] = fixity_digest
      end


    end



  end
end
