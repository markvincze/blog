+++
title = "Programmatically refreshing a browser tab from a Golang application"
slug = "programmatically-refreshing-a-browser-tab-from-a-golang-application"
description = "Programmatically refreshing a browser tab from an application can be done with a WebSocket connection. This post describes how to achieve this in Golang."
date = "2016-10-30T14:39:59.0000000"
tags = ["golang", "websocket", "livereload"]
ghostCommentId = "ghost-26"
+++

# Introduction

At work I've been working on a client-side Golang application (a command-line tool), which is used as part of the development toolchain we're using at the company.

This application is used from the command line to upload packages to our development web server, which is then opened in the browser.

Instead of opening our development site in a new tab every time, I wanted to programmatically refresh the browser tab if one has already been opened.

I initially expected this to be a pretty easy task, but after some googling I had to realize it's not trivial at all.
Apparently, there is no way to programmatically connect to the browser, query the list of tabs open, find a particular tab, and refresh it. (Especially not in a cross-browser and cross-platform way.)

After searching and asking around, I was pointed to a technology called livereload, which is both a [development tool](http://livereload.com/) and an [npm package](https://www.npmjs.com/package/livereload) for automatically refreshing the browser when editing some HTML content, or when new HTML content is being generated during the developing a website.

The way livereload works is that a component is hosting a small WebSocket service to which the browser can connect. It is also running a file watcher watching all the content (HTML, CSS, JavaScript, etc.) which should trigger a browser refresh when changed.
Then a small piece of JavaScript code in the browser connects to the WebSocket server, and refreshes the tab every time it receives a message.

The feature I wanted to implement is a bit different: I don't want to watch a particular folder containing some files and refresh the browser on changes. What I want to do is be able to programmatically trigger a refresh from code.

It turned out there is no simpler way to achieve this than to utilize the same approach which is used by `livereload`: host a small WebSocket endpoint in my Golang app, connect to it from the browser, and send a message every time I want to refresh the page.

Implementing this in Golang ended up being not too difficult, although there are a couple of gotchas you have to watch out for if your site is served over HTTPS.

# Implementing the reload server

The Websocket service we want to implement is very simple: the client (the browser) never initiates communication, it's only the server (the Golang app) that sends a message when the page has to be refreshed. We need only a single message type (with no arguments), since the only action we want to implement is the reload.

The library [`websocket`](https://github.com/gorilla/websocket) from the [Gorilla web toolkit](http://www.gorillatoolkit.org/) can be used to implement the endpoint. I based my implementation on the [Chat example](https://github.com/gorilla/websocket/tree/master/examples/chat) provided by the library (basically I tried to trim it down as much as possible, so it only contains the parts necessary for my purposes).

To host a WebSocket endpoint, we need to have some boilerplate to manage the client connections and to send messages. I took the following two files from the [Chat example](https://github.com/gorilla/websocket/tree/master/examples/chat) without much modification.

The first helper file is `wsClient.go`, which is responsible for the low level WebSocket communication.

```go
package main

import (
    "log"
    "net/http"
    "time"

    "github.com/gorilla/websocket"
)

const (
    // Time allowed to write a message to the peer.
    writeWait = 10 * time.Second

    // Time allowed to read the next pong message from the peer.
    pongWait = 60 * time.Second

    // Send pings to peer with this period. Must be less than pongWait.
    pingPeriod = (pongWait * 9) / 10
)

var (
    newline = []byte{'\n'}
    space   = []byte{' '}
)

var upgrader = websocket.Upgrader{
    ReadBufferSize:  1024,
    WriteBufferSize: 1024,
    CheckOrigin: func(r *http.Request) bool {
        return true
    },
}

// Client is an middleman between the websocket connection and the hub.
type Client struct {
    hub *Hub

    // The websocket connection.
    conn *websocket.Conn

    // Buffered channel of outbound messages.
    send chan []byte
}

// readPump pumps messages from the websocket connection to the hub.
func (c *Client) readPump() {
    defer func() {
        c.hub.unregister <- c
        c.conn.Close()
    }()
    for {
        _, _, err := c.conn.ReadMessage()
        if err != nil {
            if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway) {
                log.Printf("An error happened when reading from the Websocket client: %v", err)
            }
            break
        }
    }
}

// write writes a message with the given message type and payload.
func (c *Client) write(mt int, payload []byte) error {
    c.conn.SetWriteDeadline(time.Now().Add(writeWait))
    return c.conn.WriteMessage(mt, payload)
}

// writePump pumps messages from the hub to the websocket connection.
func (c *Client) writePump() {
    ticker := time.NewTicker(pingPeriod)
    defer func() {
        ticker.Stop()
        c.conn.Close()
    }()
    for {
        select {
        case message, ok := <-c.send:
            if !ok {
                // The hub closed the channel.
                c.write(websocket.CloseMessage, []byte{})
                return
            }

            c.conn.SetWriteDeadline(time.Now().Add(writeWait))
            w, err := c.conn.NextWriter(websocket.TextMessage)
            if err != nil {
                return
            }
            w.Write(message)

            n := len(c.send)
            for i := 0; i < n; i++ {
                w.Write(newline)
                w.Write(<-c.send)
            }

            if err := w.Close(); err != nil {
                return
            }
        case <-ticker.C:
            if err := c.write(websocket.PingMessage, []byte{}); err != nil {
                return
            }
        }
    }
}

// serveWs handles websocket requests from the peer.
func serveWs(hub *Hub, w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    if err != nil {
        log.Println(err)
        return
    }
    client := &Client{hub: hub, conn: conn, send: make(chan []byte, 256)}
    client.hub.register <- client
    go client.writePump()
    client.readPump()
}
```

Since this was originally implemented to support the two-way communication in a Chat application, probably it could be trimmed down even more.
The second file, `wsHub.go` takes care of managing the list of client connections.

```go
package main

// Hub maintains the set of active clients and broadcasts messages to the clients.
type Hub struct {
    // Registered clients.
    clients map[*Client]bool

    // Inbound messages from the clients.
    broadcast chan []byte

    // Register requests from the clients.
    register chan *Client

    // Unregister requests from clients.
    unregister chan *Client
}

func newHub() *Hub {
    return &Hub{
        broadcast:  make(chan []byte),
        register:   make(chan *Client),
        unregister: make(chan *Client),
        clients:    make(map[*Client]bool),
    }
}

func (h *Hub) run() {
    for {
        select {
        case client := <-h.register:
            h.clients[client] = true
        case client := <-h.unregister:
            if _, ok := h.clients[client]; ok {
                delete(h.clients, client)
                close(client.send)
            }
        case message := <-h.broadcast:
            for client := range h.clients {
                select {
                case client.send <- message:
                default:
                    close(client.send)
                    delete(h.clients, client)
                }
            }
        }
    }
}
```

With these helpers in place we can start up our actual WS endpoint.

```go
package main

import (
    "bytes"
    "io/ioutil"
    "log"
    "net/http"
)

var (
    hub *Hub
    // The port on which we are hosting the reload server has to be hardcoded on the client-side too.
    reloadAddress    = ":12450"
)

func startReloadServer() {
    hub = newHub()
    go hub.run()
    http.HandleFunc("/reload", func(w http.ResponseWriter, r *http.Request) {
        serveWs(hub, w, r)
    })

    go startServer()
    log.Println("Reload server listening at", reloadAddress)
}

func startServer() {
    err := http.ListenAndServe(reloadAddress, nil)

    if err != nil {
        log.Println("Failed to start up the Reload server: ", err)
        return
    }
}
```

In this example I'm hosting the service on the port `12450`, which I randomly picked from the unassigned ports in the [registry maintained by IANA](http://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml?&page=1). You can pick another port for your application, which can then be hardcoded into both the service and the client.

Calling the function `startReloadServer` at the beginning of our application will start hosting the WebSocket endpoint, and it'll keep running until our app terminates.

Then we can implement the function that will send the reload message to the browser. This is the function we have to call when we want to reload the browser.

```go
func sendReload() {
    message := bytes.TrimSpace([]byte("reload"))
    hub.broadcast <- message
}
```

In the example I'm sending the string `"reload"`, which doesn't have any role, the client won't interpret it at all, since the only function we have is reloading, which doesn't need any parameters. If we needed anything more complicated, here we could send an arbitrary message to the browser, which we can then process in JavaScript.

With all these building blocks in place the only thing we have to do is call `startReloadServer` to start hosting the service, and then call `sendReload` every time we want to refresh the browser.

```go
startReloadServer()

...

sendReload()
```

# Connecting to the Reload service

Connecting the website to the endpoint is pretty simple, but we have to keep in mind that when we open the site in the browser, our app hosting the endpoint might not run yet (or it might be stopped and restarted later). So if our site cannot connect initially, we need to periodically retry.

This can be done with the following code.

```js
function tryConnectToReload(address) {
  var conn;
  // This is a statically defined port on which the app is hosting the reload service.
  conn = new WebSocket("ws://localhost:12450/reload");

  conn.onclose = function(evt) {
    // The reload endpoint hasn't been started yet, we are retrying in 2 seconds.
    setTimeout(() => tryConnectToReload(), 2000);
  };

  conn.onmessage = function(evt) {
    console.log("Refresh received!");

    // If we uncomment this line, then the page will refresh every time a message is received.
    //location.reload()
  };
}

try {
  if (window["WebSocket"]) {
    tryConnectToReload();
  } else {
    console.log("Your browser does not support WebSocket, cannot connect to the reload service.");
  }
} catch (ex) {
  console.log('Exception during connecting to reload:', ex);
}
```

So if we call `location.reload()` in the `onmessage` handler, then the browser will be refreshed every time we receive a message.

# Problems with TLS

The above solution works perfectly as long as our website is served over plain HTTP.
This is typically the case if it's a site under development hosted on `localhost`.

On the other hand, if we access the site through HTTPS, things are a bit more tricky.

If we try to connect from a website served over HTTPS to a WebSocket endpoint hosted without TLS (over `ws://`), then — depending on the browser and the operating system — we might get the following error.

```plain
startReload.js:24 Mixed Content: The page at 'https://my-dev-application.com/' was loaded over HTTPS, but attempted to connect to the insecure WebSocket endpoint 'ws://localhost:12450/reload'. This request has been blocked; this endpoint must be available over WSS.
```

I didn't find any overview about exactly which browsers and systems produce this error. Based on my tests, this problem occurs for Chrome on Linux, but not on Windows nor OSX, and it also happens for Firefox, on every operating system I tried.

I couldn't find a perfect solution to the problem, but there is a workaround that can at least mitigate the issue. What we can do is host the WebSocket endpoint on both `ws` and `wss`, and try to connect to both from the client (first to `ws`, and if that fails, then to `wss`).

This solves the problem for both Chrome and Firefox, but there is one more thing we have to do. Since we are hosting the service on localhost, there is no way to get a valid SSL certificate, and Chrome rejects the connection by default. In order to make it ignore certificate errors when connecting to `localhost`, we have to go to the advanced settings page in Chrome by navigating to `chrome://flags`, and we have to enable the following setting.

![](/images/2016/10/chrome-ignore-localhost-cert.png)

With Firefox this didn't cause a problem, the connection worked properly after I started hosting the endpoint on `wss`. I'll update the post if I encounter any problem with it.

# Source

I uploaded the full working example to [GitHub](https://github.com/markvincze/golang-reload-browser), which also contain the implementation of hosting the reload endpoint on both WS and WSS, and also the code for the client side to establish the connection.
