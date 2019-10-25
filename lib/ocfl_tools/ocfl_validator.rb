module OcflTools
  # Class to perform checksum and structural validation of POSIX OCFL directories.

  # I'm a doof - Validator does *not* inherit Ocfl::Verify.
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
      @my_results       = Hash.new
      @my_results['errors'] = {}
      @my_results['warnings'] = {}
      @my_results['pass'] = {}

    end

    # Perform an OCFL-spec validation of the given object directory.
    # If given the optional digest value, verify file content using checksums in inventory file.
    # Will fail if digest is not found in manifest or a fixity block.
    # This validates all versions and all files in the object_root.
    # If you want to just check a specific version, call {verify_directory}.
    def validate_ocfl_object_root(digest=nil)
      @digest = digest
    end

    # Optionally, start by providing a checksum for sidecar file of the inventory.json
    def verify_checksums(inventory_file, sidecar_checksum: nil)
      # validate sidecar_checksum if present.
      # Sidecar checksum ignores @digest setting, and deduces digest to use from filename, per spec.
      # validate inventory.json checksum against inventory.json.<sha256|sha512>
      # validate files in manifest against physical copies on disk.
      # cross_check digestss.
      # Report out via @my_results.
    end

    # Do all the files and directories in the object_dir conform to spec?
    # Are there inventory.json files in each version directory? (warn if not in version dirs)
    # Deduce version dir naming convention by finding the v1 directory; apply that format to other dirs.
    def verify_structure
      # Namaste file, inventory.json and sidecar,
      # logs dir
      # version directories
      # nothing else.

      begin
        if @version_format == nil
          self.get_version_format
        end
      rescue
        error('version_format', "OCFL no appropriate version formats")
        raise "Can't determine appropriate version format"
      end

      # Onwards!
      puts "this is verify_structure"

        # get version_format might raise exception, log that here?
    end

    # We may also want to only verify the most recent directory, not the entire object.
    def verify_directory(version, digest=nil)
      # Try to load the inventory.json in the version directory *first*.
      # Only go for the root object directory if that fails.
      # Why? Because if it exists, the inventory in the version directory is the canonical inventory for that version.
      # ONLY checks that the files in this directory are present in the Manifest and (if digest is given)
      # that their checksums match. And that the files in the Manifest for this verion directory exist on disk.
    end

    # Different from verify_directory.
    # Verify_version is *all* versions of the object, up to and including this one.
    # Verify_directory is *just* check the files and checksums of inside that particular version directory.
    # Verify_version(@head) is the canonical way to check an entire object?
    def verify_version(version)
    end

    # Is the inventory file valid?
    def verify_inventory(inventory_file)
      # Load up the object with ocfl_inventory, push it through ocfl_verify.
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
      first_version = version_dirs[0]   # the first element should be the first version directory.
      first_version.slice!(0,1)         # cut the leading 'v' from the string.
      case
      when first_version.length == 1    # A length of 1 for the first version implies 'v1'
          raise "#{@ocfl_object_root}/#{first_version} is not the first version directory!" unless first_version.to_i == 1
          @version_format = "v%d"
        when first_version.length == 0
          raise "#{@ocfl_object_root} contains non-compliant directory #{version_dirs[0]}"
        else
          # Make sure this is Integer 1.
          raise "#{@ocfl_object_root}/#{first_version} is not the first version directory!" unless first_version.to_i == 1
          @version_format = "v%0#{first_version.length}d"
          pass('version_format', "OCFL conforming first version directory found.")
      end
    end

    private
    # Internal logging method.
    # @param [String] check
    # @param [String] message
    def error(check, message)
      if @my_results['errors'].key?(check) == false
        @my_results['errors'][check] = []  # add an initial empty array.
      end
      @my_results['errors'][check] = ( @my_results['errors'][check] << message )
    end

    # Internal logging method.
    # @param [String] check
    # @param [String] message
    def warning(check, message)
      if @my_results['warnings'].key?(check) == false
        @my_results['warnings'][check] = []  # add an initial empty array.
      end
      @my_results['warnings'][check] = ( @my_results['warnings'][check] << message )
    end

    # Internal logging method.
    # @param [String] check
    # @param [String] message
    def pass(check, message)
      if @my_results['pass'].key?(check) == false
        @my_results['pass'][check] = []  # add an initial empty array.
      end
      @my_results['pass'][check] = ( @my_results['pass'][check] << message )
    end
  end
end
