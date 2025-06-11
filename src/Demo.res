
let mapMapValues = (m: Map.t<'a,'b>, f: 'b => 'c) => {
  let nu = Map.make();
  m->Map.forEachWithKey((v,k) => {
    nu->Map.set(k,f(v))
  })
  nu
}


module type TERM = {
  type t
  type schematic
  type meta
  type subst = Map.t<schematic,t>
  let substitute : (t, subst) => t
  let unify : (t, t) => array<subst>
  let substDeBruijn  : (t, array<t>, ~from:int=?) => t
  let upshift : (t, int, ~from:int=?) => t    
  type gen
  let fresh : (gen, ~replacing:meta=?) => schematic
  let seen : (gen, schematic) => ()
  let place : (schematic, ~scope: array<meta>) => t
}

module type BASE = {
  module Term : TERM
  module Judgment : {
    type t
    let substitute : (t, Term.subst) => t
    let unify : (t, t) => array<Term.subst>
    let substDeBruijn  : (t, array<Term.t>, ~from:int=?) => t
    let upshift : (t, int, ~from:int=?) => t
  }
}

module ProofEngine = (Base : BASE) => {
  open Base
  module Rule = {
    type rec t = {vars: array<Term.meta>, premises: array<t>, conclusion: Judgment.t}
    let rec substitute = (rule: t, subst: Term.subst) => {
      let subst' = subst->mapMapValues(v => v->Term.upshift(Array.length(rule.vars)));
      { 
        vars: rule.vars, 
        premises: rule.premises->Array.map(premise => premise->substitute(subst')),
        conclusion: rule.conclusion->Judgment.substitute(subst')
      }
    }
    let rec substDeBruijn = (rule: t, substs: array<Term.t>, ~from:int=0) => {
      let len = Array.length(rule.vars)
      let substs' = substs->Array.map(v => v->Term.upshift(len,~from=from))
      {
        vars: rule.vars,
        premises: rule.premises
          ->Array.map(premise => premise->substDeBruijn(substs', ~from=from+len)),
        conclusion: rule.conclusion
          ->Judgment.substDeBruijn(substs',~from=from+len),
      }
    }
    let rec upshift = (rule: t, amount: int, ~from:int=0) => {
      let len = Array.length(rule.vars)
      {
        vars: rule.vars,
        premises: rule.premises->Array.map(r => r->upshift(amount, ~from = from + len)),
        conclusion: rule.conclusion->Judgment.upshift(amount, ~from = from + len)
      }
    }
    type bare = { premises: array<t>, conclusion: Judgment.t }
    let instantiate = (rule: t, terms: array<Term.t>) => {
      assert(Array.length(terms) == Array.length(rule.vars))
      let terms' = [...terms]
      Array.reverse(terms')
      {
        premises: rule.premises->Array.map(r => r-> substDeBruijn(terms')),
        conclusion: rule.conclusion->Judgment.substDeBruijn(terms')
      }
    }
  }
  module Step = {
    type t<'a> = {
      fixes: array<Term.meta>, 
      facts: Dict.t<Rule.t>,
      proof: 'a
    }
    let bind : (t<'a>, 'a => t<'b>) => t<'b> = (s, f) => {
      let t = f(s.proof);
      { 
        fixes: t.fixes->Array.concat(s.fixes),
        facts: Dict.copy(s.facts)->Dict.assign(t.facts),
        proof: t.proof
      }
    }
  }
  module Goal = {
    type t = {
      fix: array<Term.meta>, 
      assume: array<Rule.t>, 
      assumeNames: array<string>, 
      show: Judgment.t 
    }
    let toRule : t => Rule.t = (goal : t) => {
      vars: goal.fix,
      premises: goal.assume,
      conclusion: goal.show
    }
  }
  module type PROOFT = {
    type t<'a>
    let subproofs : (Goal.t,t<'a>, 'a=>Goal.t) => Dict.t<Step.t<'a>>
  }
  module Either = (A : PROOFT, B : PROOFT) => {
    type t<'a> = L(A.t<'a>) | R(B.t<'a>)
    let subproofs = (goal:Goal.t,it : t<'a>, f : 'a => Goal.t) => switch it {
    | L(x) => A.subproofs(goal,x,f)
    | R(x) => B.subproofs(goal,x,f)
    }
  }
  
  module Deduction : PROOFT = {
    type t<'a> = {
      from: array<'a>,
      ruleName: string,
      instantiation: array<Term.t>
    }
    let subproofs = (goal : Goal.t,it : t<'a>, _ : 'a => Goal.t) => {
      let toStep : 'a => Step.t<'a> = (a) => {
        fixes: goal.fix, 
        facts: Belt.Array.zip(goal.assumeNames,goal.assume)->Dict.fromArray,
        proof: a
      };
      Belt.Array.range(0,Array.length(it.from))
        ->Array.map(x =>Belt.Int.toString(x))
        ->Belt.Array.zip(it.from->Array.map(toStep))
        ->Dict.fromArray
    }
  }
  module Lemma : PROOFT = {
    type t<'a> = {
      name: string,
      have: 'a,
      show: 'a
    }
    let subproofs = (goal: Goal.t,it : t<'a>, f : 'a => Goal.t) => {
      let haveGoal : Step.t<'a> = {
        fixes: goal.fix, 
        facts: Belt.Array.zip(goal.assumeNames,goal.assume)->Dict.fromArray,
        proof: it.have
      };
      let showGoal : Step.t<'a> = {
        fixes: goal.fix, 
        facts: Belt.Array.zip(goal.assumeNames,goal.assume)
          ->Array.concat([(it.name,f(it.have)->Goal.toRule)])
          ->Dict.fromArray,
        proof: it.show
      };
      Dict.fromArray([(it.name,haveGoal), ("@show",showGoal)])
    }
  }
  module Proof = (A : PROOFT) => {
    type rec t = {goal:Goal.t, step?: A.t<t> }
  }
}

module FirstOrder = ProofEngine({
  module Term = SExp
  module Judgment = SExp
})
open FirstOrder

module TestProofs = Proof(Either(Deduction,Lemma))