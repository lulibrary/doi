# suppress output
ActiveRecord::Base.logger = nil

# make a new instance
m = DoisController.new

# do the update
m.batch