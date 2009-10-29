
srv:
    if @desired['goog'] && @desired['goog'] != 'mail'
      desired.update({ 
        "_xmpp-server._tcp.#{@zone.origin}" => {
          '0 5269 xmpp-server.l.google.com.' => 5, '0 5269 xmpp-server1.l.google.com.' => 20,
          '0 5269 xmpp-server2.l.google.com.' => 20, '0 5269 xmpp-server3.l.google.com.' => 20,
          '0 5269 xmpp-server4.l.google.com.' => 20
        },
        "_jabber._tcp.#{@zone.origin}" => {
          '0 5269 xmpp-server.l.google.com.' => 5, '0 5269 xmpp-server1.l.google.com.' => 20,
          '0 5269 xmpp-server2.l.google.com.' => 20, '0 5269 xmpp-server3.l.google.com.' => 20,
          '0 5269 xmpp-server4.l.google.com.' => 20
        },
        "_xmpp-client._tcp.#{@zone.origin}" => {
          '0 5222 talk.l.google.com.' => 5, '0 5222 talk1.l.google.com.' => 20, 
          '0 5222 talk2.l.google.com.' => 20
        }
      })
    end
    
txt:
    if @desired['goog'] && ! desired.any? {|t| t.match(/^v=spf1/)}
      desired << "v=spf1 include:aspmx.googlemail.com ~all"
    end

mx:
    if @desired['goog']
      desired = {
        'aspmx.l.google.com.' => 1, 'alt1.aspmx.l.google.com.' => 5, 'alt2.aspmx.l.google.com.' => 5, 
        'aspmx2.googlemail.com.' => 10, 'aspmx3.googlemail.com.' => 10, 'aspmx4.googlemail.com.' => 10,
        'aspmx5.googlemail.com.' => 10
      }
    end
    
