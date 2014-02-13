class CommitMonitorHandlers::BugzillaCommentor
  include Sidekiq::Worker

  delegate :product, :to => :CommitMonitor

  def perform(branch_id, commit, message)
    branch = CommitMonitorBranch.find(branch_id)
    process_commit(branch, commit, message)
  end

  private

  def process_commit(branch, commit, message)
    prefix     = "New commit detected on #{branch.repo.name}/#{branch.name}:"
    commit_uri = branch.commit_uri_to(commit)
    comment    = "#{prefix}\n#{commit_uri}\n\n#{message}"

    message.each_line do |line|
      match = %r{^\s*https://bugzilla\.redhat\.com/show_bug\.cgi\?id=(?<bug_id>\d+)$}.match(line)
      write_to_bugzilla(match[:bug_id], comment) if match
    end
  end

  def write_to_bugzilla(bug_id, comment)
    log_prefix = "#{self.class.name}##{__method__}"
    logger.info("#{log_prefix} Updating bug id #{bug_id} in Bugzilla.")

    BugzillaService.call do |bz|
      output = bz.query(:product => product, :bug_id => bug_id).chomp
      if output.empty?
        logger.error "#{log_prefix} Unable to write for bug id #{bug_id}: Not a '#{product}' bug."
      else
        logger.info "#{log_prefix} Writing to bugzilla for bug id #{bug_id}"
        bz.modify(bug_id, :comment => comment)
      end
    end
  rescue => err
    logger.error "#{log_prefix} Unable to write for bug id #{bug_id}: #{err}"
  end
end