import { Component } from './componentgraph'
import { view as Test } from './Test.mjs'
import { testParse } from './SExp.mjs'
import ReactDOM from 'react-dom/client';
import React from 'react';

  
export default class TestComponent implements Component {
	data : string;
	dependencyChanged : (id: string, comp: Component) => void;
	toString() {
		return this.data;
	}
	constructor(str : string, deps : Record<string,Component>, signal : (msg: any) => void, view? : HTMLElement) {
		this.data = testParse(str,["a","b","c"]);
		if (view != null) {
			let root = ReactDOM.createRoot(view);
			root.render(<Test judgment={this.data} scope={["a","b","c"]} />)
		}
		this.dependencyChanged = (_depName, _comp) => { };
	}
}