#!/usr/bin/ruby
#
# Copyright 2009 (C) Rick Branson. Meh, it's public domain.
#

require "rubygems"
require "right_aws"

SECONDS_IN_DAY = 24 * 60 * 60

config = YAML.load_file(ARGV[0] || "config.yml")

ec2 = RightAws::Ec2.new(config["AWS_ACCESS_KEY"], config["AWS_SECRET_KEY"])
insts = ec2.describe_instances
vols = ec2.describe_volumes.select { |v| v[:aws_attachment_status] == "attached" }
snaps = ec2.describe_snapshots.select { |s| vols.any? { |v| v[:aws_id] == s[:aws_volume_id] } }

puts "===> Snapshot Cleanup"

# Go thru snapshots, delete "completed" ones for "available" instances that
# are configured days old.
snaps.select { |s| s[:aws_status] == "completed" }.each do |s|
  age = ((Time.now - s[:aws_started_at]) / SECONDS_IN_DAY).floor
  puts " #{s[:aws_id]} (=> #{s[:aws_volume_id]}) is #{age} days old."

  if age > config["SNAPSHOT_MAX_DAYS"]
    # leave at least one snapshot around
    if snaps.select { |alt| alt[:aws_volume_id] == s[:aws_volume_id] }.size <= 1
      puts "  Would delete #{s[:aws_id]}, but it's the only one left for #{s[:aws_volume_id]}!"
    else
      puts "  Deleting #{s[:aws_id]}..."
      ec2.delete_snapshot(s[:aws_id])
    end
  end
end

puts ""
puts "===> Snapshot Creation"

# Create new snapshots
vols.each do |v|
  inst = insts.find { |i| i[:aws_instance_id] == v[:aws_instance_id] }
  sg = inst[:aws_groups].reject { |g| inst[:aws_groups].size > 1 and g == "default" }.join(", ")
  puts " Volume #{v[:aws_id]} (#{v[:aws_size]}GB) => #{v[:aws_instance_id]} (#{sg})"

  snap = ec2.create_snapshot(v[:aws_id])
  puts "  Snapshot Created: #{snap[:aws_id]}"
end
