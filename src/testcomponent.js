import * as ComponentGraph from './main.ts'
import { LitElement, html } from 'https://cdn.jsdelivr.net/gh/lit/dist@3/core/lit-core.min.js';
class MyElement extends LitElement {
	static properties = {
		version: {},
		deps: {},
	};
  
	constructor(str, deps, signal) {
		super();
		this.deps = deps;
		this.content = str;
		this.signal = signal;
	}
	changeText(event) {
		this.content = event.target.value;
		this.signal("TEXTCHANGED");
	}
	render() {
		const itemTemplates = [];
		for (const i in this.deps) {
			itemTemplates.push(html`<li>${i}:${this.deps[i].data.content}</li>`);
		}
		return html`
	  <textarea @change=${this.changeText}>${this.content}</textarea>
	  <ul>${itemTemplates}</ul>
	  `;
	}
}
customElements.define('my-element', MyElement);
  
export default class TestComponent {
	toString() {
		return this.data.content;
	}
	constructor(str, deps, signal, view) {
		view.innerHTML = "";
		var element = new MyElement(str, deps, signal);
		this.data = element;
		view.appendChild(element);
		this.dependencyChanged = (_depName, _comp) => { element.requestUpdate(); };
	}
}