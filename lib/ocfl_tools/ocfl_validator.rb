module OcflTools
  # Class to perform checksum and structural validation of POSIX OCFL directories.
  class OcflValidator

    # @return [Pathname] ocfl_object_root the full local filesystem path to the OCFL object root directory.
    attr_reader :ocfl_object_root

    # @return [String] version_format the discovered version format of the object, found by inspecting version directory names.
    attr_reader :version_format

    # @param [Pathname] ocfl_storage_root is a the full local filesystem path to the object directory.
    def initialize(ocfl_object_root)
      @digest           = nil
      @version_format   = nil
      @ocfl_object_root = ocfl_object_root
      @my_results       = OcflTools::OcflResults.new
    end

    # @return [OcflTools::OcflResults] results of validation results.
    def results
      @my_results
    end

    # Perform an OCFL-spec validation of the given object directory.
    # If given the optional digest value, verify file content using checksums in inventory file.
    # Will fail if digest is not found in manifest or a fixity block.
    # This validates all versions and all files in the object_root.
    # If you want to just check a specific version, call {verify_directory}.
    def validate_ocfl_object_root(digest=nil)
      @digest = digest
      # calls verify_structure, verify_inventory and verify_checksums.
      self.verify_structure
      self.verify_inventory # returns a diff. results object; merge it?
      self.verify_checksums
    end

    def get_version_directories
      object_root_dirs = []
      Dir.chdir(@ocfl_object_root)
      Dir.glob('*').select do |file|
         if File.directory? file
           object_root_dirs << file
         end
      end
      version_directories = [] # we need this for later.

      # Find all directories with names that match version_format.
      object_root_dirs.each  do |i|
        if i =~ /[^"{@version_format}"$]/
          version_directories << i
        end
      end
      return version_directories
    end

    # The default checksum test assumes you want to test all likely files on disk against
    # whatever version of the inventory.json (hopefully the latest!) is in the root directory.
    def verify_checksums(inventory_file=nil)
      # validate inventory.json checksum against inventory.json.<sha256|sha512>
      # validate files in manifest against physical copies on disk.
      # cross_check digestss.
      # Report out via @my_results.
      if inventory_file == nil
        inventory_file = "#{@ocfl_object_root}/inventory.json"
      end

      inventory = OcflTools::OcflInventory.new.from_file(inventory_file)
      # We're checking all files, so just get the manifest.
      version_directories = self.get_version_directories

      # if @digest is set, use that as the digest for checksumming.
      # ( but check inventory.fixity to make sure it's there first )
      # Otherwise, use the value of inventory.digestAlgorithm

      files_on_disk = []

      version_directories.each do | ver |
        files = Dir.glob("#{@ocfl_object_root}/#{ver}/#{inventory.contentDirectory}/**/*").select{ |e| File.file? e }
        files.each{ |f| files_on_disk << f }
      end

      # Generate disk checksums.
      disk_checksums = Hash.new

      files_on_disk.each do | f |
        disk_checksums[f] = "#{OcflTools::Utils.generate_file_digest(f, inventory.digestAlgorithm)}"
      end

      # Get an equivalent hash by manipulating the inventory.manifest hash.
      # We're going to edit this, so make sure we don't mess with the manifest version.
      temp_checksums = OcflTools::Utils.deep_copy(inventory.manifest).invert

      # This is where, if there's a request for a digest that's NOT the inventory's digestAlgo,
      # we'd have to go to inventory.fixity and look there instead.

      # Gives us array of files for key, checksum as value.
      manifest_checksums = {}
      temp_checksums.each do | my_array, my_digest |
        # key is an array that might have multiple values in it; all files with same digest. Expand / flatten it.
       my_array.each do | f |
          manifest_checksums["#{@ocfl_object_root}/#{f}"] = my_digest
        end
      end
      # We now have 2 Hashes; 1 generated by inspecting each file on disk and calculating a digest
      # and the other by expanding & flipping the inventory.manifest, so each key is a full file path.

      @my_results = OcflTools::Utils.compare_hash_checksums(disk_checksums, manifest_checksums, @my_results)

    end

    # Given a full directory path, parse the top of inventory.json for the OCFL digestAlgorithm value.
    # Why not just use OcflTools.config.digest_algorithm? Because we may not know, when given a random
    # directory, what the digest_algorithm is meant to be. It might not be the site-wide setting. Heck,
    # there may not even *be* a site. So we do need to try and get it from an inventory.json in the object dir.
    def get_digestAlgorithm(directory)
      # Using IO.foreach and lazy.grep to minimize cost of checking large inventory.json files.
      result = IO.foreach("#{directory}/inventory.json").lazy.grep(/digestAlgorithm/).take(1).to_a #{ |a| puts "I got #{a}"}
      # [ " "digestAlgorithm": "sha256"," ] is my return value. It's not great.
      string = result[0]  # our result is an array with an singl element.
      result_array = string.split('"') # and we need the 4th element.
      result_array[3]
      # DO SOMETHING if file is not found;
      # Also, we are assuming that it's actually a well-enough formed version of inventory.json.
    end

    # Do all the files and directories in the object_dir conform to spec?
    # Are there inventory.json files in each version directory? (warn if not in version dirs)
    # Deduce version dir naming convention by finding the v1 directory; apply that format to other dirs.
    def verify_structure

      error = nil

      begin
        if @version_format == nil
          self.get_version_format
        end
      rescue
        @my_results.error('E111', 'version_format', "OCFL unable to determine version format by inspection of directories.")
        error = true
        # raise "Can't determine appropriate version format"
        # The rest of the method simply won't work without @version_format.
        @version_format = OcflTools.config.version_format
        @my_results.warn('W111', 'version_format', "Attempting to process using default value: #{OcflTools.config.version_format}")
      end

      object_root_dirs  = []
      object_root_files = []

      Dir.chdir(@ocfl_object_root)
      Dir.glob('*').select do |file|
         if File.directory? file
           object_root_dirs << file
         end
         if File.file? file
           object_root_files << file
         end
      end

      # CHECK for required files.
      # We have to check the top of inventory.json to get the appropriate digest algo.
      # This is so we don't cause get_digestAlgorithm to throw up if inventory.json doesn't exist.
      file_checks = []
      file_checks << "inventory.json"

      if File.exist? "#{@ocfl_object_root}/inventory.json"
        json_digest = self.get_digestAlgorithm(@ocfl_object_root)
        file_checks << "inventory.json.#{json_digest}"
      end

      file_checks << "0=ocfl_object_1.0"

      file_checks.each do | file |
        if object_root_files.include? file == false
          @my_results.error('E111', 'verify_structure', "OCFL 3.1 Object root does not include required file #{file}")
          error = true
        end
        # we found it, delete it and go to next.
        object_root_files.delete(file)
      end

      # Array should be empty! If not, we have extraneous files in object root.
      if object_root_files.size != 0
        @my_results.error('E111', 'verify_structure', "OCFL 3.1 Object root contains noncompliant files: #{object_root_files}")
        error = true
      end

      # CHECK DIRECTORIES
      # logs are optional.
      if object_root_dirs.include? 'logs'
        @my_results.warn('W111', 'verify_structure', "OCFL 3.1 optional logs directory found in object root.")
        object_root_dirs.delete('logs')
      end

      version_directories = [] # we need this for later.

      # Find all directories with names that match version_format.
      object_root_dirs.each  do |i|
        if i =~ /[^"{@version_format}"$]/
          version_directories << i
        end
      end

      remaining_dirs = object_root_dirs - version_directories

      # Any content left in object_root_dirs are not compliant. Log them!
      if remaining_dirs.size > 0
        @my_results.error('E111', 'verify_structure', "OCFL 3.1 Object root contains noncompliant directories: #{remaining_dirs}")
        error = true
      end

      # Now process the version directories we *did* find.
      # Must be a continuous sequence, starting at v1.
      version_directories.sort!
      version_dir_count = version_directories.size
      count = 0

      until count == version_dir_count
        count += 1
        expected_directory = @version_format % count
        # just check to see if it's in the array version_directories.
        # We're not *SURE* that what we have is a continous sequence starting at 1;
        # just that they're valid version dir names and they exist.
        if version_directories.include? expected_directory
          # puts "I found expected directory #{expected_directory}"
        else
          @my_results.error('E111', 'verify_structure', "OCFL 3.1 Expected version directory #{expected_directory} missing from sequence #{version_directories} ")
          error = true
        end
      end

      # For the version_directories we *do* have, are they cool?
      version_directories.each do | ver |
        # Do a file and dir glob.
        version_dirs  = []
        version_files = []

        Dir.chdir("#{@ocfl_object_root}/#{ver}")
        Dir.glob('*').select do |file|
           if File.directory? file
             version_dirs << file
           end
           if File.file? file
             version_files << file
           end
        end

        # only two files here, but only warn if they're not present.
        file_checks = []
        if File.exist? "#{@ocfl_object_root}/#{ver}/inventory.json"
          json_digest = self.get_digestAlgorithm("#{@ocfl_object_root}/#{ver}")
          file_checks << "inventory.json"
          file_checks << "inventory.json.#{json_digest}"
        else
          file_checks << "inventory.json"
        end

        file_checks.each do | file |
          if version_files.include? file
            version_files.delete(file)
            else
            @my_results.warn('W111', 'verify_structure', "OCFL 3.1 optional #{file} missing from #{ver} directory")
            version_files.delete(file)
          end
        end

        if version_files.size > 0
          @my_results.error('E111', 'verify_structure', "OCFL 3.1 non-compliant files #{version_files} in #{ver} directory")
          error = true
        end

        if version_dirs.include? OcflTools.config.content_directory
          version_dirs.delete(OcflTools.config.content_directory)
          else
          @my_results.error('E111', 'verify_structure', "OCFL 3.1 required content directory #{OcflTools.config.content_directory} not found in #{ver} directory")
          error = true
        end

        if version_dirs.size > 0
          @my_results.error('E111', 'version_structure', "OCFL 3.1 noncompliant directories #{version_dirs} found in #{ver} directory")
          error = true
        end

      end

      # If we get here without errors (warnings are OK), we passed!
      if error == nil
        @my_results.ok('O111', 'verify_structure', "OCFL 3.1 Object root passed file structure test.")
      end
      return @my_results
    end

    # We may also want to only verify the most recent directory, not the entire object.
    def verify_directory(version, digest=nil)
      # Try to load the inventory.json in the version directory *first*.
      # Only go for the root object directory if that fails.
      # Why? Because if it exists, the inventory in the version directory is the canonical inventory for that version.
      # ONLY checks that the files in this directory are present in the Manifest and (if digest is given)
      # that their checksums match. And that the files in the Manifest for this verion directory exist on disk.
      #
      # Plan:
      # 1. Load the inventory file in that version dir, if present.
      #    If not present, load the root inventory file (and verify that version is in it;check @list_version_id)
      # 2. Glob all files in given object_dir/version_dir/content_dir.
      # 3. Copy, Flatten and flip inventory.manifest or fixity block. (we want filepaths as keys, digest as values)
      # 4. Process the flipped manifest to get only files add/modifed in given version.
      # 5. Now generate digests for the files found on disk.
      # 6. Do a checksum compare (new Utils#method?).
    end

    # Different from verify_directory.
    # Verify_version is *all* versions of the object, up to and including this one.
    # Verify_directory is *just* check the files and checksums of inside that particular version directory.
    # Verify_version(@head) is the canonical way to check an entire object?
    def verify_version(version)
    end

    # Is the inventory file valid?
    # @return [OcflTools::OcflResults] of verification results.
    def verify_inventory(inventory_file=nil)
      if inventory_file == nil
        inventory_file = "#{@ocfl_object_root}/inventory.json"
      end
      # Load up the object with ocfl_inventory, push it through ocfl_verify.
      inventory = OcflTools::OcflInventory.new.from_file(inventory_file)
      OcflTools::OcflVerify.new(inventory).check_all
    end

    # Do all the files mentioned in the inventory(s) exist on disk?
    # This is an existence check, not a checksum verification.
    def verify_files
      # Calls verify_directory for each version?
    end

    # find the first directory and deduce the version format. set @version_format appropriately.
    def get_version_format
      # Get all directories starting with 'v', sort them.
      # Take the top of the sort. Count the number of 0s found.
      # Raises errors if it can't find an appropriate version 1 directory.
      version_dirs = []
      Dir.chdir(@ocfl_object_root)
      Dir.glob('v*').select do |file|
         if File.directory? file
           version_dirs << file
         end
      end
      version_dirs.sort!
      # if there's a verson_dirs that's just 'v', throw it out! It's hot garbage edge case we'll deal with later.
      if version_dirs.include? 'v'
        version_dirs.delete('v')
      end

      first_version = version_dirs[0]   # the first element should be the first version directory.
      first_version.slice!(0,1)         # cut the leading 'v' from the string.
      case
      when first_version.length == 1    # A length of 1 for the first version implies 'v1'
          raise "#{@ocfl_object_root}/#{first_version} is not the first version directory!" unless first_version.to_i == 1
          @version_format = "v%d"
        else
          # Make sure this is Integer 1.
          raise "#{@ocfl_object_root}/#{first_version} is not the first version directory!" unless first_version.to_i == 1
          @version_format = "v%0#{first_version.length}d"
          @my_results.ok('O111', 'version_format', "OCFL conforming first version directory found.")
      end
    end

  end
end
