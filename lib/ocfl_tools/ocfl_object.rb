module OcflTools
  # Class that represents the data structures of an OCFL inventory file.
  class OcflObject
    attr_accessor :manifest, :versions, :fixity, :id, :digestAlgorithm, :head, :type, :contentDirectory

    def initialize
      # Parameters that must be serialized into JSON
      @id               = nil
      @head             = nil
      @type             = OcflTools.config.content_type
      @digestAlgorithm  = OcflTools.config.digest_algorithm # sha512 is recommended, Stanford uses sha256.
      @contentDirectory = OcflTools.config.content_directory # default is 'content', Stanford uses 'data'
      @manifest         = Hash.new
      @versions         = Hash.new # A hash of Version hashes.
      @fixity           = Hash.new # Optional. Same format as Manifest.
    end

    # sets @head in current string format, when given integer.
    # @param [Integer] version to set head to.
    # @return {@head} value of most recent version.
    def set_head_from_version(version)
      @head = OcflTools::Utils.version_int_to_string(version)
    end

    # sets the message field for a given version.
    # @param [Integer] version of OCFL object to set message for.
    # @param [String] message to set for given version.
    # @note will raise an exception if you attempt to query a non-existent version.
    def set_version_message(version, message)
      raise "Version #{version} does not yet exist!" unless @versions.key?(OcflTools::Utils.version_int_to_string(version))
      @versions[OcflTools::Utils.version_int_to_string(version)]['message'] = message
    end

    # returns the message field for a given version.
    # @param [Integer] version of OCFL object to get the message for.
    # @return [String] message set for the given version, if any.
    # @note will raise an exception if you attempt to query a non-existent version.
    def get_version_message(version)
      raise "Version #{version} does not yet exist!" unless @versions.key?(OcflTools::Utils.version_int_to_string(version))
      @versions[OcflTools::Utils.version_int_to_string(version)]['message']
    end

    # Sets the user Hash for a given version. Expects a complete User hash (with sub-keys of name & address).
    # @param [Integer] version of OCFL object to set the user block for.
    # @param [Hash] user block to set for this version. Must be a hash with two keys 'name' and 'address'.
    # @note will raise an exception if you attempt to query a nonexistent version.
    def set_version_user(version, user)
      raise "Version #{version} does not yet exist!" unless @versions.key?(OcflTools::Utils.version_int_to_string(version))
      @versions[OcflTools::Utils.version_int_to_string(version)]['user'] = user
    end

    # Gets the user Hash for a given version.
    # @ param [Integer] version of OCFL object to retrieve user block for.
    # @return [Hash] user block for this version, a hash consisting of two keys, 'name' and 'address'.
    # @note will raise an exception if you attempt to query a nonexistent version.
    def get_version_user(version)
      raise "Version #{version} does not yet exist!" unless @versions.key?(OcflTools::Utils.version_int_to_string(version))
      @versions[OcflTools::Utils.version_int_to_string(version)]['user']
    end

    # Gets an array of integers comprising all versions of this OCFL object. It is not guaranteed to be in numeric order.
    # @return [Array{Integer}] versions that exist in the object.
    def version_id_list
      my_versions = []
      @versions.keys.each do | key |
        my_versions << OcflTools::Utils.version_string_to_int(key)
      end
      my_versions
    end

    # Gets the state block of a given version, comprising of digest keys and an array of filenames associated with those digests.
    # @param [Integer] version of OCFL object to retreive version state block of.
    # @return [Hash] of digests and array of pathnames associated with this version.
    def get_state(version)
      # @param [Integer] version to get state block of.
      # @return [Hash] state block.
      # Creates version and copies prior state if it doesn't already exist.
      my_version = self.get_version(version)
      return my_version['state']
    end

    # Sets the state block for a given version when provided with a hash of digest keys and an array of associated filenames.
    # @param [Integer] version of object to set state for.
    # @param [Hash] hash of digests (keys) and an array of pathnames (values) associated with those digests.
    # @note It is prefered to update version state via add/update/delete/copy/move file operations.
    def set_state(version, hash)
      # SAN Check needed here to make sure passed Hash has all expected keys.
      @versions[OcflTools::Utils.version_int_to_string(version)]['state'] = hash
    end

    # Gets a hash of all logical files and their associated physical filepaths with the given version.
    # @param [Integer] version from which to generate file list.
    # @return [Hash] of files, with logical file as key, physical location within object dir as value.
    def get_files(version)
      my_state = self.get_state(version)
      my_files = Hash.new

      my_state.each do | digest, filepaths | # filepaths is [Array]
        filepaths.each do | logical_filepath |
          # look up this file via digest in @manifest.
          physical_filepath = @manifest[digest]
          # physical_filepath is an [Array] of files, but they're all the same so only need 1.
          my_files[logical_filepath] = physical_filepath[0]
        end
      end
      my_files
    end

    # Gets all files for the current (highest) version of the OCFL object. Represents the state of the object at 'head',
    # with the logical files that consist of the most recent version and their physical representations on disk, relative
    # to the object's root directory.
    # @return [Hash] of files from most recent version, with logical file as key, associated physical filepath as value.
    def get_current_files
      self.get_files(OcflTools::Utils.version_string_to_int(@head))
    end

    # Adds a file to a version.
    # @param [Pathname] file is the logical filename within the object.
    # @param [String] digest of filename, presumably computed with the {digestAlgorithm} for the object.
    # @param [Integer] version to add file to.
    # @return [Hash] state block reflecting the version after the changes.
    # @note will raise an error if an attempt is made to add a file to a prior (non-head) version. Will also raise an error if the requested file already exists in this version with a different digest: use {update_file} instead.
    def add_file(file, digest, version)
      # new digest, new filename, update manifest.
      # We use get_state here instead of asking @versions directly
      # because get_state will create version hash if it doesn't already exist.
      my_state = self.get_state(version)

      raise "Can't edit prior versions! Only version #{version} can be modified now." unless version == self.version_id_list.sort[-1]

      if my_state.key?(digest)
        # file's already in this version. Add file to existing digest.
        my_files = my_state[digest]
        my_files << file
        unique_files = my_files.uniq # Just in case we're trying to add the same thing multiple times.
        # Need to actually add this to @versions!
        @versions[OcflTools::Utils.version_int_to_string(version)]['state'][digest] = unique_files
        # Prove we actually added to state
        # Also need to add to @manifest!
        self.update_manifest(file, digest, version)
        return self.get_state(version)
      end

      # Check to make sure the file isn't already in this state with a different digest!
      # If so; fail. We don't do implicit / soft adds. You want that, be explict: do an update_file instead.
      existing_files = self.get_files(version)
      if existing_files.key?(file)
        raise "File already exists with different digest in this version! Consider update instead."
      end

      # if it's not in State already, just add it.
      @versions[OcflTools::Utils.version_int_to_string(version)]['state'][digest] = [ file ]
      self.update_manifest(file, digest, version)
      return self.get_state(version)
    end

    # Updates an existing file with a new bitstream and digest.
    # @param [String] file filepath to update.
    # @param [String] digest of updated file.
    # @param [Integer] version of object to update.
    # @note this method explicitly deletes the prior file if found, and re-creates it with a new digest via the {add_file} method.
    def update_file(file, digest, version)
      # Same filename, different digest, update manifest.
      # Do a Delete, then an Add.
      existing_files = self.get_files(version)

      if existing_files.key?(file)
        self.delete_file(file, version)
      end
      self.add_file(file, digest, version)
    end

    # @note internal API.
    def update_manifest(file, digest, version)
      # We only ever add to the manifest.
      # So if this digest exists, return the original source (physical path)
      # or add new physical path if file not seen before.

      # This is where we'd have to do dedupe? Maybe with some indirection
      # that checks for a DEDUPE constant being set? Or we assume Dedupe for now,
      # and enable the optional no-dedupe later.
      if @manifest.key?(digest)
        # The file is already in the manifest, don't need to add again.
        # Just return the original path.
        return @manifest[digest]
      end
      # otherwise, add to manifest.
      physical_filepath = "#{OcflTools::Utils.version_int_to_string(version)}/#{@contentDirectory}/#{file}"
      @manifest[digest] = [ physical_filepath ]
      return @manifest[digest]
    end

    # Given a filepath, deletes that file from the given version. If multiple copies of the same file
    # (as identified by a common digest) exist in the version, only the requested filepath is removed.
    # @param [Pathname] file logical path of file to be deleted.
    # @param [Integer] version version of object to delete file from.
    # @return [Hash] state of version after delete has completed.
    def delete_file(file, version)
      # remove filename, may remove digest if that was last file associated with that digest.
      my_state = self.get_state(version) # Creates version & copies state from prior version if doesn't exist.

      raise "Can't edit prior versions! Only version #{version} can be modified now." unless version == self.version_id_list.sort[-1]

      my_digest = self.get_digest(file, version)
      # we know it's here b/c self.get_digest would have crapped out if not.
      my_array = my_state[my_digest]  # Get [Array] of files that have this digest in this version.
      my_array.delete(file)           # Delete the array value that matches file.
      if my_array.length > 0
        # update the array with (fewer) items.
        my_state[my_digest] = my_array
      else
        # delete the key.
        my_state.delete(my_digest)
      end
      # put results back into State.
      self.set_state(version, my_state)
    end

    # Copies a file within the same version. If the destination file already exists with a different digest,
    # it is overwritten with the digest of the source file.
    # @param [Filepath] source_file filepath of source file.
    # @param [Filepath] destination_file filepath of destination file.
    # @param [Integer] version version of OCFL object.
    # @return [Hash] state block of version after file copy has completed.
    # @note Raises an error if source_file does not exist in this version.
    def copy_file(source_file, destination_file, version)
      # add new filename to existing digest.
      # If destination file already exists, overwrite it.
      existing_files = self.get_files(version)

      if existing_files.key?(destination_file)
        self.delete_file(destination_file, version)
      end
      self.add_file(destination_file, self.get_digest(source_file, version), version)
    end

    # Moves (renames) a file from one location to another within the same version.
    # @param [Pathname] old_file filepath to move.
    # @param [Pathname] new_file new filepath.
    # @return [Hash] state block of version after file copy has completed.
    # @note This is functionally a {copy_file} followed by a {delete_file}. Will raise an error if the source file does not exist in this version.
    def move_file(old_file, new_file, version)
      # re-name; functionally a copy and delete.
      self.copy_file(old_file, new_file, version)
      self.delete_file(old_file, version)
    end

    # @param [Pathname] file
    # @param [Integer] version
    def get_digest(file, version)
      # Make a hash with each individual file as a key, with the appropriate digest as value.
      inverted = self.get_state(version).invert
      my_files = {}
      inverted.each do | files, digest |
        files.each do | file |
          my_files[file] = digest
        end
      end
      # Now see if the requested file is actually here.
      raise "Get_digest can't find requested file in given version!" unless my_files.key?(file)
      return my_files[file]
    end

    def get_version(version)
      # @param [Integer] version
      # @return [Hash] version block, if it exists, or creates new with prior version state in it.
      if @versions.key?(OcflTools::Utils.version_int_to_string(version))
        return @versions[OcflTools::Utils.version_int_to_string(version)]
      else
      # Otherwise, construct a new Version [Hash] and return that.
      @versions[OcflTools::Utils.version_int_to_string(version)] = self.create_version_hash

      # If version -1 exists, copy prior version state over.
      if @versions.key?(OcflTools::Utils.version_int_to_string(version - 1))
        @versions[OcflTools::Utils.version_int_to_string(version)]['state'] = OcflTools::Utils.deep_copy(@versions[OcflTools::Utils.version_int_to_string(version - 1)]['state'])
      end

      return @versions[OcflTools::Utils.version_int_to_string(version)]
      end
    end

    # @note internal API
    def create_version_hash
      # @return [Hash] blank version Hash.
      # creates a blank version hash.
      new_version = Hash.new
      new_version['created'] = ''
      new_version['message'] = ''
      new_version['user'] = Hash.new
        # user is #name, # address.
      new_version['user']['name'] = ''
      new_version['user']['address'] = ''
      new_version['state'] = Hash.new
      return new_version
    end

    def set_version(version, hash)
      # SAN Check to make sure passed Hash has all expected keys.
      @versions[OcflTools::Utils.version_int_to_string(version)] = hash
    end

  end
end
