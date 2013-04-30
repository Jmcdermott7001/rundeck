#
# Cookbook Name:: wt_storm_streaming
# Recipe:: default
#
# Copyright 2012, Webtrends
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

download_url = node['wt_storm_streaming']['download_url']
install_tmp = '/tmp/wt_storm_install'
tarball = 'streaming-analysis-bin.tar.gz'

if node.recipes.include?("recipe[storm::nimbus]")
  is_nimbus = true
end

if is_nimbus
  nimbus_host = node[:fqdn]
else
  nimbus_host = search(:node, "role:storm_nimbus AND role:#{node['storm']['cluster_role']} AND chef_environment:#{node.chef_environment}").first[:fqdn]
end
# grab the zookeeper port
zookeeper_clientport = node['zookeeper']['client_port']

# grab the zookeeper nodes that are currently available
zookeeper_quorum = Array.new
if not Chef::Config.solo
    search(:node, "role:zookeeper AND chef_environment:#{node.chef_environment}").each do |n|
        zookeeper_quorum << n['fqdn']
    end
end

kafka = search(:node, "role:kafka_aggregator AND chef_environment:#{node.chef_environment}").first
pod = node['wt_realtime_hadoop']['pod']
datacenter = node['wt_realtime_hadoop']['datacenter']
zookeeper_root = "/#{datacenter}_#{pod}_storm-streaming"
transactional_zookeeper_root = "/#{datacenter}_#{pod}_storm-streaming-transactional"

#############################################################################
# Storm jars

# Before adding a jar here make sure it's in the repo (i.e.-
# http://repo.staging.dmz/repo/linux/storm/jars/), otherwise the run
# of chef-client will fail

# Perform a deploy if the deploy flag is set
if ENV["deploy_build"] == "true" then
    log "The deploy_build value is true so we will grab the tar ball and install"
    
    # delete previous the install TEMP directory
    directory install_tmp do
      owner "root"
      group "root"
      mode 00755
      recursive true
      action :delete
    end
end

directory install_tmp do
  owner "root"
  group "root"
  mode 00755
  recursive true
  action :create
end

# grab the source file
remote_file "#{install_tmp}/#{tarball}" do
  source download_url
  mode 00644
  action :create_if_missing
end

# extract the source file into TEMP directory
execute "topo_tar" do
  user  "root"
  group "root"
  cwd install_tmp
  creates "#{install_tmp}/lib"
  command "tar zxvf #{install_tmp}/#{tarball}"
end

execute "mv" do
  user  "root"
  group "root"
  command "mv #{install_tmp}/lib/webtrends*.jar #{node['storm']['lib_dir']}"
  action :nothing
  subscribes :run, "execute[topo_tar]"
end

# Remove any old zookeeper lib, below we will replace it.
execute "rm" do
  user  "root"
  group "root"
  command "rm -f #{node['storm']['lib_dir']}/zookeeper*.jar"
  action :nothing
  subscribes :run, "execute[topo_tar]"
end

%w{
activation-1.1.jar
antlr-3.4.jar
antlr-runtime-3.4.jar
antlr4-4.0.jar
antlr4-runtime-4.0.jar
aopalliance-1.0.jar
avro-1.5.3.jar
avro-ipc-1.5.3.jar
commons-cli-1.2.jar
commons-collections-3.2.1.jar
commons-configuration-1.6.jar
commons-el-1.0.jar
commons-httpclient-3.1.jar
commons-math-2.1.jar
commons-net-1.4.1.jar
curator-framework-1.0.3.jar
curator-recipes-1.1.10.jar
fastutil-6.4.4.jar
groovy-all-1.7.6.jar
guice-3.0.jar
guice-assisted-inject-3.0.jar
gson-2.2.2.jar
hadoop-core-1.0.0.jar
hamcrest-core-1.1.jar
hbase-0.92.0.jar
high-scale-lib-1.1.1.jar
jackson-core-asl-1.9.3.jar
jackson-jaxrs-1.5.5.jar
jackson-mapper-asl-1.9.3.jar
jackson-xc-1.5.5.jar
jamm-0.2.5.jar
JavaEWAH-0.5.0.jar
javax.inject-1.jar
jdom-1.1.jar
jersey-core-1.4.jar
jersey-json-1.4.jar
jersey-server-1.4.jar
jettison-1.1.jar
jsp-2.1-6.1.14.jar
jsp-api-2.1-6.1.14.jar
kafka_2.9.2-0.7.2.jar
libthrift-0.7.0.jar
netty-3.5.11.Final.jar
plexus-utils-1.5.6.jar
protobuf-java-2.4.0a.jar
regexp-1.3.jar
stax-api-1.0.1.jar
scala-library-2.9.2.jar
streaming-analysis.jar
UserAgentUtils-1.6.jar
xmlenc-0.52.jar
zkclient-0.1.jar
mobi.mtld.da-1.5.3.jar
ini4j-0.5.2.jar
metrics-annotation-2.2.0.jar
metrics-core-2.2.0.jar
metrics-guice-2.2.0.jar
zookeeper-3.3.6.jar
}.each do |jar|
  execute "mv #{jar}" do
    user  "root"
    group "root"
    command "mv #{install_tmp}/lib/#{jar} #{node['storm']['lib_dir']}/#{jar}"
    action :nothing
    subscribes :run, "execute[topo_tar]"
  end
end

execute "chown" do
  user  "root"
  group "root"
  command "chown storm:storm -R #{node['storm']['install_dir']}"
end

# template out the log4j config with our custom logging settings
template "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}/log4j/storm.log.properties" do
	source  "storm.log.properties.erb"
	owner "storm"
	group "storm"
	mode  00644
end

# create the log directory
directory "#{node['storm']['conf_dir']}/cache" do
  action :create
  owner "storm"
  group "storm"
  mode 00755
end

file "#{node['storm']['conf_dir']}/storm.yaml" do
  owner "root"
  group "root"
  mode "00644"
  action :delete
end

# template the storm yaml file
template "#{node['storm']['conf_dir']}/storm.yaml" do
  source "storm.yaml.erb"
  owner  "storm"
  group  "storm"
  mode   00644
  variables(
    :worker_childopts => node['storm']['worker']['childopts'],
    :zookeeper_root => zookeeper_root,
    :transactional_zookeeper_root => transactional_zookeeper_root,
    :storm_config => node['wt_storm_streaming'],
    :zookeeper_quorum => zookeeper_quorum,
    :zookeeper_clientport  => zookeeper_clientport,
    :nimbus_host => nimbus_host
  )
end

# # template the actual storm config file
# template "#{node['storm']['conf_dir']}/application.conf" do
#   source "application.conf.erb"
#   owner  "storm"
#   group  "storm"
#   mode   00644
#   variables(
#     :visitor_pod => node['wt_storm_streaming']['visitor']['pod'],
#     :visitor_datacenter => node['wt_storm_streaming']['visitor']['datacenter'],
#     :visitor_hbase_table_partitions => node['wt_storm_streaming']['visitor']['hbase_table_partitions'],
#     :visitor_hbase_table_direct => node['wt_storm_streaming']['visitor']['hbase_table_direct'],
#     :visitor_hbase_table_parallel => node['wt_storm_streaming']['visitor']['hbase_table_parallel'],
#     :visitor_zookeeper_quorum => node['wt_storm_streaming']['visitor']['zookeeper_quorum']
#   )
# end

# template the actual storm config file
template "#{node['storm']['conf_dir']}/config.properties" do
  source "config.properties.erb"
  owner  "storm"
  group  "storm"
  mode   00644
  variables(
    # executor counts, ie: executor threads
    :event_stream_bolt_tasks => node['wt_storm_streaming']['event_stream_bolt_tasks'],
    :event_stream_bolt_executors => node['wt_storm_streaming']['event_stream_bolt_executors'],
    :session_stream_bolt_tasks => node['wt_storm_streaming']['session_stream_bolt_tasks'],
    :session_stream_bolt_executors => node['wt_storm_streaming']['session_stream_bolt_executors'],    
    :augment_bolt_tasks => node['wt_storm_streaming']['augment_bolt_tasks'],
    :augment_bolt_executors => node['wt_storm_streaming']['augment_bolt_executors'],
    :response_bolt_tasks => node['wt_storm_streaming']['response_bolt_tasks'],
    :response_bolt_executors => node['wt_storm_streaming']['response_bolt_executors'],

    # kafka consumer settings
    :kafka_consumer_topic       => node['wt_storm_streaming']['topic_list'].join(','),
    :kafka_consumer_group_id    => node['wt_storm_streaming']['kafka']['consumer_group_id'],
    :kafka_zookeeper_timeout_ms => node['wt_storm_streaming']['kafka']['zookeeper_timeout_ms'],
    :kafka_auto_offset_reset    => node['wt_storm_streaming']['kafka']['auto_offset_reset'],
    :kafka_auto_commit_enable   => node['wt_storm_streaming']['kafka']['auto_commit_enable'],
    # tracer dcsid
    :tracer_dcsid => node['wt_storm_streaming']['tracer_dcsid'],
    # non-storm parameters
    :zookeeper_quorum      => zookeeper_quorum * ",",
    :configservice         => node['wt_streamingconfigservice']['config_service_url'],
    :netacuity             => node['wt_netacuity']['geo_url'],
    :pod                   => pod,
    :datacenter            => datacenter,
    :audit_zookeeper_pairs => zookeeper_quorum.map { |server| "#{server}:#{zookeeper_clientport}" } * ",",
    :audit_bucket_timespan => node['wt_monitoring']['audit_bucket_timespan'],
    :audit_topic           => node['wt_monitoring']['audit_topic'],
    :cam_url               => node['wt_cam']['cam_service_url'],
    :data_request_url      => node['wt_storm_streaming']['data_request_url']
  )
end

template "#{node['storm']['conf_dir']}/log4j.properties" do
  source "log4j.properties.erb"
  owner  "storm"
  group  "storm"
  mode   00644
  variables(
  )
end

%w{
botIP.csv
asn_org.csv
conn_speed_code.csv
city_codes.csv
country_codes.csv
metro_codes.csv
region_codes.csv
keywords.ini
device-atlas.json
browsers.ini
convert_searchstr.ini
}.each do |ini_file|
    cookbook_file "#{node['storm']['conf_dir']}/#{ini_file}" do
      source ini_file
      mode 00644
    end
end

if is_nimbus
  execute "reload_streaming_nimbus" do
    command "sv reload nimbus"
    action :nothing
    subscribes :run, resources(:template => "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}/conf/config.properties"), :immediately
  end

  execute "reload_streaming_webui" do
    command "sv reload stormui"
    action :nothing
    subscribes :run, resources(:template => "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}/conf/config.properties"), :immediately
  end

  # execute "start-topo" do
  #   command "bin/storm jar lib/streaming-analysis.jar com.webtrends.streaming.analysis.storm.topology.StreamingTopology"
  #   user "storm"
  #   cwd "/opt/storm/current"
  #   action :nothing
  #   subscribes :run, "execute[tar]"
  # end   
else #Node must be supervisor
  execute "reload_streaming_supervisor" do
    command "sv reload supervisor"
    action :nothing
    subscribes :run, resources(:template => "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}/conf/config.properties"), :immediately
  end
end