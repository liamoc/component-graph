import { Component } from './main'
import { LitElement, html } from 'lit';
import { customElement, property } from 'lit/decorators.js';

@customElement('my-element')
class MyElement extends LitElement {
    @property()
	content: string
	@property()
	deps: Record<string,TestComponent>
	signal: (msg: any) => void
	
	constructor(str : string, deps : Record<string,Component>, 
		signal : (msg: any) => void) {
		super();
		this.deps = deps as Record<string,TestComponent>;
		this.content = str;
		this.signal = signal;
	}
	changeText(event : Event) {
		this.content = (event.target as HTMLTextAreaElement).value;
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
  
export default class TestComponent {
	data : MyElement;
	dependencyChanged : (id: string, comp: Component) => void;
	toString() {
		return this.data.content;
	}
	constructor(str : string, deps : Record<string,Component>, signal : (msg: any) => void, view? : HTMLElement) {
		view.innerHTML = "";
		var element = new MyElement(str, deps, signal);
		this.data = element;
		view.appendChild(element);
		this.dependencyChanged = (_depName, _comp) => { element.requestUpdate(); };
	}
}