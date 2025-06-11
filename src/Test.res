open Demo
module type TERM_VIEW = {
  module Term : TERM
  let view : (~term: Term.t, ~scope: array<Term.meta>) => React.element
}

module type BASE_VIEW = {
  module Base : BASE 
  module TermView : TERM_VIEW with module Term := Base.Term;
  module JudgmentView : {
    open Base
    type props = {judgment: Judgment.t, scope: array<Term.meta>}
    let view : props => React.element
  }
}

module SExpView : TERM_VIEW with module Term := SExp = {
  let viewVar = (idx, scope:array<string>) => {
    switch scope[idx] {
    | Some(n) if Array.indexOf(scope,n) == idx => <span className="var"> { React.string(n) } </span>
    | _ => <span className="var_unnamed"> {React.string("\\")} { React.int(idx) } </span>
    }
  }
  let parenthesise = (f) =>
    [React.string("("),...f,React.string(")")]
  let intersperse = (a) => a->Array.flatMapWithIndex((e, i) => 
    if i == 0 { [e] } else { [React.string(" "),e] })
  let rec view = (~term: SExp.t, ~scope: array<string>) => switch term {
  | Compound({subexps:bits}) => {
      <span className="compound">
      {bits
        ->Array.map(t => view(~term= t, ~scope=scope))
        ->intersperse->parenthesise->React.array} 
      </span>
      }
  | Var({idx:idx}) => viewVar(idx,scope)
  | Symbol({name:s}) => <span className="symbol"> { React.string(s) } </span>
  | Schematic({schematic:s, allowed:vs}) => <span className="schematic">{React.string("?")} {React.int(s)} <span className="schematic_allowed">{vs->Array.map(v => viewVar(v,scope))->intersperse->parenthesise->React.array}</span></span>
  }
}

module SExpBaseView : BASE_VIEW = {
  module Base = { module Term = SExp; module Judgment = SExp }
  module TermView = SExpView
  module JudgmentView = {
    open Base
    type props = {judgment: Judgment.t, scope: array<Term.meta>}
    let view = props => TermView.view(~term=props.judgment, ~scope=props.scope)
  }
}

include SExpBaseView.JudgmentView

