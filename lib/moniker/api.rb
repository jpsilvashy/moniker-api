# Need this to have the right IP address for accessing Moniker via API
require "moniker/api/version"
require 'moniker/proxy_ssh'
require 'nokogiri'
require 'open-uri'

# m = Moniker::Api.new('moniker-account', 'moniker-password')
# m.domains
# m.register_domain('a-new-domain.com', ['ns1.pointhq.com','ns2.pointhq.com'], 'id' )
class NokogiriWrap
  def get(loc); @parser = Nokogiri::XML.parse(open(loc)); end
  attr_reader :parser
end

module Moniker
  class Api
    def initialize(token, password, ssh_host: nil, ssh_user: nil)
      @token = token
      @password = password
      @domains  = nil
      if(ssh_host)
        @agent = Moniker::ProxySSH.new(ssh_host, ssh_user, nil)
      else
        @agent = NokogiriWrap.new
      end
    end
    
    def agent; @agent; end
    def domains
      agent.get("http://api.moniker.com/pub/ExternalApi?cmd=domainsearch&account=#{@token}&password=#{@password}&client-ref=myrefnumber&action=all")
      if agent.parser.xpath("//MonikerTransaction/status").attribute("code").value.to_i != 200
        ip = agent.parser.xpath("//MonikerTransaction/request/ip").text
        raise agent.parser.xpath("//MonikerTransaction/status").text + ". Add: #{ip} to account at http://moniker.com"
      end
      agent.parser.xpath('//domain').collect { |e| { :name => e.text.downcase,
                                                    :ns1 => e.attribute('ns1').value,
                                                    :ns2 => e.attribute('ns2').value,
                                                    :ns3 => e.attribute('ns3').value,
                                                    :ns4 => e.attribute('ns4').value,
                                                    :ns5 => e.attribute('ns5').value,
                                                    :ns6 => e.attribute('ns6').value  } }
    end
    def account_info()
      res = agent.get("http://api.moniker.com/pub/ExternalApi?cmd=accountinfo&account=#{@token}&password=#{@password}&client-ref=myrefnumber")
      if res.xpath("//MonikerTransaction/status").attribute("code").value.to_i != 200
        raise res.xpath("//MonikerTransaction/status").text
      end
      { 
        balance: res.xpath('//MonikerTransaction/response/account').attribute('balance').value,
        firstname: res.xpath('//MonikerTransaction/response/account').attribute('firstname').value,
        lastname: res.xpath('//MonikerTransaction/response/account').attribute('lastname').value
      }
    end
    def register_domain(domain, nameservers, nic)
      dom_string = "#{domain}:1" # For multiple: test1.com:1;test2.com:1 -- 1 = years to reg for
      res = agent.get("http://api.moniker.com/pub/ExternalApi?cmd=domainregister&account=#{@token}&password=#{@password}&client-ref=myrefnumber&Lock_Req=YES&Agree=YES&domains=#{dom_string}&Admin_Nic=#{nic}&Bill_Nic=#{nic}&Tech_Nic=#{nic}&Reg_Nic=#{nic}&Primary_NS=#{nameservers.first}&Secondary_NS=#{nameservers[1]}&category=RubyMonikerAPI")
      if res.xpath("//MonikerTransaction/status").attribute("code").value.to_i != 200
        raise res.xpath("//MonikerTransaction/status").text
      end
      if res.xpath("//MonikerTransaction/response/domain").attribute("code").value.to_i != 200
        raise res.xpath("//MonikerTransaction/response/domain").attribute("msg").text
      end
      raise "Domain Unavailable" if res.text =~ /All Domains Unavailable/
      res
    end
    def update_domain(domain, nameservers)
      dom_string = "#{domain}"
      res = agent.get("http://api.moniker.com/pub/ExternalApi?cmd=domainupdate&account=#{@token}&password=#{@password}&client-ref=myrefnumber&Agree=YES&domains=#{dom_string}&Primary_NS=#{nameservers.first}&Secondary_NS=#{nameservers[1]}&Tertiary_NS=&Quaternary_NS=&Quintenary_NS=&Sextenary_NS=")
      puts res
      raise "Domain not updated" unless res.text =~ /Success/
    end
    def domain_details(domain)
      dom_string = "#{domain}"
      res = agent.get("http://api.moniker.com/pub/ExternalApi?cmd=domaininfo&account=#{@token}&password=#{@password}&client-ref=myrefnumber&domain=#{dom_string}")
      if res.xpath("//MonikerTransaction/status").attribute("code").value.to_i != 200
        raise res.xpath("//MonikerTransaction/status").text
      end
      nameservers = {}
      nameservers[:ns1] = res.xpath("//MonikerTransaction/response/domain").attribute("ns1").value
      nameservers[:ns2] = res.xpath("//MonikerTransaction/response/domain").attribute("ns2").value
      nameservers[:ns3] = res.xpath("//MonikerTransaction/response/domain").attribute("ns3").value
      nameservers[:ns4] = res.xpath("//MonikerTransaction/response/domain").attribute("ns4").value
      nameservers[:ns5] = res.xpath("//MonikerTransaction/response/domain").attribute("ns5").value
      nameservers[:ns6] = res.xpath("//MonikerTransaction/response/domain").attribute("ns6").value
      admin_nic   = res.xpath("//MonikerTransaction/response/domain").attribute("admin").value
      billing_nic = res.xpath("//MonikerTransaction/response/domain").attribute("billing").value
      tech_nic    = res.xpath("//MonikerTransaction/response/domain").attribute("tech").value
      date_created = res.xpath("//MonikerTransaction/response/domain").attribute("date_created").value
      date_updated = res.xpath("//MonikerTransaction/response/domain").attribute("date_updated").value
      date_expired = res.xpath("//MonikerTransaction/response/domain").attribute("date_expired").value
      renew_auto   = res.xpath("//MonikerTransaction/response/domain").attribute("renew_auto").value == "1"
      { nameservers: nameservers, admin_nic: admin_nic, billing_nic: billing_nic, tech_nic: tech_nic,
        created_at: date_created, updated_at: date_updated, expires_ad: date_expired, auto_renew: renew_auto }
    end
    def domain_available?(domain)
      agent.get("http://api.moniker.com/pub/ExternalApi?cmd=domaincheck&account=#{@token}&password=#{@password}&client-ref=myrefnumber&domains=#{dom_string}")
      agent.page.body !~ /Domain Unavailable/
    end
  end
end
