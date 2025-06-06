import ms from 'ms';
import lunchtime from './lunchtime.js';
import millisecondsUntil from './millisecondsUntil.js';

interface Component {
	data: any;
	toString() : string;
	initialise(d: string) : void;
}

let toInitialise : Array<string> = [];
export async function load(url:string) : Promise<Handler> {
	if (url in database) {
		return database[url];
	} else {
		let requestURI = url.split('/').slice(0,-1).join("/");
		let response = await fetch(requestURI);
		let body = await response.text();
		const parser = new DOMParser();
		const htmldoc = parser.parseFromString(body,"text/html")
		/*let host = document.createElement("div");
		host.style.border = "1px solid red";
		document.body.appendChild(host);
		let shadow = host.attachShadow({ mode: "open" });
		for (let x of knownTags) {
	    for (let y  of htmldoc.querySelectorAll(x)) {
				shadow.appendChild(document.adoptNode(y));		
			}
		}*/
		for (let x of knownTags) {
			for (let y  of htmldoc.querySelectorAll(x)) {
				window.customElements.upgrade(document.adoptNode(y))
			}
		}
		while (toInitialise.length) {
			database[toInitialise.shift()??""]?.initialise();
		}
		if (!(url in database)) {
			throw "ERROR"
		} else {
			return database[url];
		}
	}
}

class Handler {
	url:string;
	component : Component | null;
	subscribers : Array<Handler>;
	deps: Record<string,Handler | null>;
	status : "loading" | "ready";
	
	addSubscriber(h:Handler) {
		this.subscribers.push(h);
		if (this.status == "ready") {
			h.dependencyReady(this.url)
		}
	}
	initialise: () => void;
  dependencyReady: (url: string) => void;
	
	constructor(url:string,textual:string, deps: Array<string>, maker: new(data:string, deps:Record<string,Component>, view?:HTMLElement)=>Component, view?:HTMLElement) {
		this.url=url;
		this.status = "loading";
		this.deps = {};
		let awaiting = [];
		this.subscribers = [];
		for (let dep of deps) {
			if (dep != "") {
				awaiting.push(dep);
				this.deps[dep] = null;
			}
		}		
		this.component = null;
		this.initialise = function() {
			for (let dep in this.deps) {
				load(dep).then((h) => {
					this.deps[dep] = h;
					h.addSubscriber(this);
				})
			}		
			if (awaiting.length == 0) {
				this.component = new maker(textual, {}, view);
				this.status = "ready";
				for (let sub of this.subscribers) {
					sub.dependencyReady(this.url);
				}
			}
		}
		this.dependencyReady = function(url) {
			let index = awaiting.indexOf(url);
			if (index > -1) {
				awaiting.splice(index,1);
			}
			
			if (awaiting.length == 0) {
				let deps2 : Record<string,Component> = {};
				for (let dep in this.deps) {
					if (this.deps[dep]?.component != null) {
						deps2[dep] = this.deps[dep].component;
					}
				}
				this.component = new maker(textual,deps2,view);
				this.status = "ready";
				for (let sub of this.subscribers) {
					sub.dependencyReady(this.url);
				}
			}
		}
	}
}
let knownTags : Array<string>  = [];
export let database : Record<string,Handler> = {};
/*
*/

export function registerTag(name: string, maker: new(data:string, deps:Record<string,Component>,view?:HTMLElement)=>Component) {
	knownTags.push(name);
	
	window.customElements.define(name,class extends HTMLElement {
		constructor() {
			super();
			let id = this.attributes.getNamedItem("id")?.value ?? "default";
			toInitialise.push(id);
			let deps = (this.attributes.getNamedItem("deps")?.value ?? "").split(" ");
			let text = this.innerHTML;
			this.innerHTML = "loading";
			database[this.id] = new Handler(this.id,text,deps,maker,this);
		}
	})
	window.customElements.whenDefined(name).then(() => {
		while (toInitialise.length) {
		  database[toInitialise.shift()??""]?.initialise();
		}
	})
}