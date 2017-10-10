require 'rugged'

module GitService
  class Branch
    attr_reader :branch
    def initialize(branch)
      @branch = branch
    end

    def content_at(path)
      blob_at(path).try(:content)
    end

    def diff
      Diff.new(target_for_reference(merge_target_ref_name).diff(merge_tree))
    end

    def mergeable?
      merge_tree
      true
    rescue UnmergeableError
      false
    end

    def merge_base
      rugged_repo.merge_base(target_for_reference(merge_target_ref_name), target_for_reference(ref_name))
    end

    def merge_index # Rugged::Index for a merge of this branch
      rugged_repo.merge_commits(target_for_reference(merge_target_ref_name), target_for_reference(ref_name))
    end

    def merge_tree # Rugged::Tree object for the merge of this branch
      tree_ref = merge_index.write_tree(rugged_repo)
      rugged_repo.lookup(tree_ref)
    rescue Rugged::IndexError
      raise UnmergeableError
    ensure
      # Rugged seems to allocate large C structures, but not many Ruby objects,
      #   and thus doesn't trigger a GC, so we will trigger one manually.
      GC.start
    end

    def tip_commit
      target_for_reference(ref_name)
    end

    def tip_tree
      tip_commit.tree
    end

    def target_for_reference(reference) # Rugged::Commit for a given refname i.e. "refs/remotes/origin/master"
      rugged_repo.references[reference].target
    end

    def tip_files
      recursive_list_files_in_tree(tip_tree.oid)
    end

    private

    def recursive_list_files_in_tree(rugged_tree_oid, files = [], current_path = Pathname.new(""))
      rugged_repo.lookup(rugged_tree_oid).each do |i|
        full_path = current_path.join(i[:name])
        case i[:type]
        when :blob
          files << full_path.to_s
        when :tree
          recursive_list_files_in_tree(i[:oid], files, full_path)
        end
      end
      files
    end

    def ref_name
      return "refs/#{branch.name}" if branch.name.include?("prs/")
      "refs/remotes/origin/#{branch.name}"
    end

    def merge_target_ref_name
      "refs/remotes/origin/#{branch.merge_target}"
    end

    def blob_at(path) # Rugged::Blob object for a given file path on this branch
      blob_data = tip_tree.path(path)
      blob = Rugged::Blob.lookup(rugged_repo, blob_data[:oid])
      blob.type == :blob ? blob : nil
    rescue Rugged::TreeError
      nil
    end

    def rugged_repo
      @rugged_repo ||= Rugged::Repository.new(branch.repo.path.to_s)
    end
  end
end
