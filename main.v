/*
Copyright (C) 2023 Jack Chakany <jack@chaker.net>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

module main

import net.websocket
import x.json2
import term

fn main() {
	println('Starting up lol')
	relays := ['wss://relay.damus.io', 'wss://relay.snort.social']
	// whitelisted := [0, 1]
	mut from_channels := []chan string{} // out of relay
	mut to_channels := []chan string{} // to relay

	for relay in relays {
		new_from_chan := chan string{}
		from_channels << new_from_chan
		new_to_chan := chan string{}
		to_channels << new_to_chan
		spawn listen_to_relay(relay, new_to_chan, new_from_chan)
	}

	listenforevents(from_channels, to_channels)
}

fn listenforevents(from_channels []chan string, to_channels []chan string) {
	for channel in from_channels {
		for {
			select {
				ev := <-channel {
					handle_event(to_channels, ev)
				}
			}
		}
	}
}

struct Event {
	id         string
	sig        string
	pubkey     string
	kind       int
	content    string
	tags       [][]string
	subject    string
	created_at int
}

type RelayMessage = Event | string

fn handle_event(channels []chan string, event string) ? {
	mut event_decoded := json2.raw_decode(event) or {
		eprintln('Error: ${err}')
		return
	}
	conv_arr := event_decoded.arr()
	println(conv_arr[0].str())
	if conv_arr[0].str() == 'EVENT' {
		encoded := json2.encode([conv_arr[0], conv_arr[2]])
		println(encoded)
		for channel in channels {
			channel <- encoded
		}
	}
}

fn listen_to_relay(url string, to_ch chan string, from_ch chan string) {
	mut ws := websocket.new_client(url) or {
		eprintln('error: ${err}')
		return
	}

	ws.on_open(fn (mut ws websocket.Client) ! {
		ws.write_string('["REQ", "FUCKINGVTESTSUB", { "kinds": [1] }]') or {
			eprintln('error writing to server: ${err}')
			return
		}
	})

	ws.on_message(fn [from_ch] (mut ws websocket.Client, msg &websocket.Message) ! {
		from_ch <- msg.payload.bytestr()
		println('msg recieved: ${msg.payload.bytestr()}')
	})

	ws.on_error(fn (mut ws websocket.Client, err string) ! {
		println(term.red('ws.on_error error: ${err}'))
	})

	ws.on_close(fn (mut ws websocket.Client, code int, reason string) ! {
		println('socket closed:  ${reason}')
	})

	ws.connect() or { eprintln('error connecting: ${err}') }

	spawn fn [mut ws, to_ch, url] () {
		for {
			select {
				ev := <-to_ch {
					println('Recieved message for broadcast - ${url} : ${ev}')
					ws.write_string(ev) or { eprintln('error when trying to broadcast: ${err}') }
				}
			}
		}
	}()

	ws.listen() or { eprint('error listening: ${err}') }
}
