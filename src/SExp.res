module IntCmp = Belt.Id.MakeComparable({type t = int;let cmp = Pervasives.compare })


type rec t =
    Symbol({name: string }) 
  | Compound({subexps: array<t>}) 
  | Var({idx:int}) 
  | Schematic({schematic:int, allowed: array<int>})
type meta = string
type schematic = int
type subst = Map.t<schematic,t>
let rec schematicsIn : (t) => Belt.Set.t<int, IntCmp.identity> = (it : t) => switch it {
| Schematic({schematic,_}) => Belt.Set.make(~id=module(IntCmp))->Belt.Set.add(schematic)
| Compound({subexps}) => subexps->Array.reduce(
    Belt.Set.make(~id=module(IntCmp)), 
    (s, x) => Belt.Set.union(s, schematicsIn(x))
  )
| _ => Belt.Set.make(~id=module(IntCmp))
}
let rec freeVarsIn : (t) => Belt.Set.t<int, IntCmp.identity> = (it : t) => switch it {
| Var({idx}) => Belt.Set.make(~id=module(IntCmp))->Belt.Set.add(idx)
| Compound({subexps}) => subexps->Array.reduce(
    Belt.Set.make(~id=module(IntCmp)), 
    (s, x) => Belt.Set.union(s, freeVarsIn(x))
  )
| _ => Belt.Set.make(~id=module(IntCmp))
}
let rec substitute = (term: t, subst: subst) => switch term {
| Compound({subexps}) => 
    Compound({subexps: Array.map(subexps, x => substitute(x,subst))})
| Schematic({schematic, _}) => switch Map.get(subst,schematic) {
  | None => term
  | Some(found) => found
  }
| _ => term
}

let combineSubst = (s : subst, t: subst) => {
  let nu = Map.make();
  Map.entries(s)->Iterator.forEach(opt => switch opt {
  | None => ()
  | Some((key,term)) => nu->Map.set(key, term->substitute(t))
  })
  Map.entries(t)->Iterator.forEach(opt => switch opt {
  | None => ()
  | Some((key,term)) => nu->Map.set(key, term->substitute(s))
  })
  nu
}
let emptySubst : subst = Map.make()
let singletonSubst : (int, t) => subst = (schematic,term) => {
  let s = Map.make()
  s->Map.set(schematic,term)
  s
}
let rec unifyTerm = (a: t, b: t) => switch (a,b) {
| (Symbol({name:na}), Symbol({name:nb})) if na == nb => Some(emptySubst)
| (Var({idx:ia}), Var({idx:ib})) if ia == ib => Some(emptySubst)
| (Schematic({schematic:sa,_}), Schematic({schematic:sb,_})) if sa == sb => Some(emptySubst)
| (Compound({subexps:xa}), Compound({subexps:xb})) if Array.length(xa) == Array.length(xb) =>
  unifyArray(Belt.Array.zip(xa,xb))
| (Schematic({schematic,allowed}), t)
  if !Belt.Set.has(schematicsIn(t), schematic)
  && Belt.Set.subset(freeVarsIn(t), Belt.Set.fromArray(allowed,~id=module(IntCmp))) 
  => Some(singletonSubst(schematic,t))
| (t, Schematic({schematic,allowed}))
  if !Belt.Set.has(schematicsIn(t), schematic)
  && Belt.Set.subset(freeVarsIn(t), Belt.Set.fromArray(allowed,~id=module(IntCmp)))
  => Some(singletonSubst(schematic,t))
| (_,_) => None
}
and unifyArray = (a: array<(t,t)>) => {
  if (Array.length(a) == 0) {
    Some(emptySubst)
  } else {
    let (x,y) = a[0]->Option.getUnsafe
    switch unifyTerm(x,y) {
    | None     => None
    | Some(s1) => {
        switch a
          ->Array.sliceToEnd(~start=1)
          ->Array.map(((t1,t2)) => (substitute(t1,s1),substitute(t2,s1)))
          ->unifyArray {
        | None     => None
        | Some(s2) => Some(combineSubst(s1,s2))
        }
      }
    }
  }
}
let unify = (a: t, b: t) => {
  switch unifyTerm(a,b) {
  | None => []
  | Some(s) => [s]
  }
}
let rec substDeBruijn = (term: t, substs: array<t>, ~from:int=0) => switch term {
| Symbol(_) => term
| Compound({subexps}) => 
    Compound({subexps: Array.map(subexps, x => substDeBruijn(x,substs,~from=from))})
| Var({idx:var}) => if (var < from) {
    term
  } else if (var - from < Array.length(substs) && var - from >= 0) {
    Option.getUnsafe(substs[var - from])
  } else {
    Var({idx: var - Array.length(substs) })
  }
| Schematic({schematic,allowed}) =>
    Schematic({schematic, allowed: 
      Array.filterMap(allowed, i =>
        if (i < from + Array.length(substs)) { 
          None 
        } else { 
          Some(i - (from + Array.length(substs)))
        }
      )
    })
}
let rec upshift = (term: t, amount: int, ~from:int=0) => switch term {
| Symbol(_) => term
| Compound({subexps}) => 
    Compound({subexps: Array.map(subexps, x => upshift(x,amount,~from=from))})
| Var({idx}) => Var({idx: if (idx >= from) { idx + amount } else { idx }})
| Schematic({schematic,allowed}) =>
    Schematic({schematic, allowed: 
      Array.map(allowed, i => if (i >= from) { i + amount } else { i })
    })
}
let place = (x : int,~scope: array<string>)
  => Schematic({schematic:x,allowed: Array.fromInitializer(~length=Array.length(scope), i=>i)})
type gen = ref<int>
let seen = (g : gen, s : int) => {
  if (s >= g.contents) { 
    g := s + 1
  }
}
let fresh = (g : gen, ~replacing as _ =?) => {
  let v = g.contents
  g := g.contents + 1
  v
}

type error = string

let symbolRegexpString = "^([^\\s()]+)";
let varRegexpString = "^\\\\([0-9]+)$";
let schematicRegexpString = "^\\?([0-9]+)$";
type lexeme = LParen | RParen | VarT(int) | SymbolT(string) | SchematicT(int)

let parse = (str: string, ~scope: array<string>, ~gen: gen) => {
  let cur = ref(String.make(str));
  let lex : () => option<lexeme> = () => {
    let str = String.trim(cur.contents);
    cur := str
    let checkVariable = (candidate: string) => {
      let varRegexp = RegExp.fromString(varRegexpString)
      switch (Array.indexOf(scope,candidate)) {
      | -1 => switch varRegexp->RegExp.exec(candidate) {
        | Some(res') => switch RegExp.Result.matches(res') {
          | [idx] => Some(idx->Int.fromString->Option.getUnsafe)
          | _ => None
          }
        | None => None
        }
      | idx => Some(idx)
      }
    }
    if (String.get(str,0) == Some("(")) {
      cur := String.sliceToEnd(str,~start=1)
      Some(LParen)
    } else if (String.get(str,0) == Some(")")) {
      cur := String.sliceToEnd(str,~start=1)
      Some(RParen)
    } else {
      let symbolRegexp = RegExp.fromStringWithFlags(symbolRegexpString,~flags="y")
      switch symbolRegexp->RegExp.exec(str) {
      | None => None
      | Some(res) => switch RegExp.Result.matches(res) {
        | [symb] => {
            cur := String.sliceToEnd(str,~start=RegExp.lastIndex(symbolRegexp))
            switch checkVariable(symb) {
            | Some(idx) => Some(VarT(idx))
            | None => {
                let schematicRegexp = RegExp.fromString(schematicRegexpString)
                switch schematicRegexp->RegExp.exec(symb) {
                | None => Some(SymbolT(symb))
                | Some(res') => switch RegExp.Result.matches(res') {
                  | [s] => Some(SchematicT(s->Int.fromString->Option.getUnsafe))
                  | _ => Some(SymbolT(symb))
                  }
                }
              }
            }
          }
        | _ => None
        }
      }
    }
  }
  
  let peek = () => {
    // a bit slow, better would be to keep a backlog of lexed tokens..
    let str = String.make(cur.contents)
    let tok = lex()
    cur := str
    tok  
  }
  exception ParseError(string)
  let rec parseExp = () => {
    let tok = peek()
    switch tok {
    | Some(SymbolT(s)) => { let _ = lex(); Some(Symbol({name: s})) }
    | Some(VarT(idx)) => { let _ = lex(); Some(Var({idx: idx})) }
    | Some(SchematicT(num)) => {
        let _ = lex();
        switch lex() {
        | Some(LParen) => {
            let it = ref(None)
            let bits = [];
            let getVar = (t : option<lexeme>) => switch t {
            | Some(VarT(idx)) => Some(idx)
            | _ => None
            }
            while {it := lex(); it.contents->getVar->Option.isSome} {
              Array.push(bits, it.contents->getVar->Option.getUnsafe)
            }
            switch it.contents {
            | Some(RParen) => {
                seen(gen,num);
                Some(Schematic({schematic: num, allowed: bits }))
              }
            | _ => raise(ParseError("Expected closing parenthesis"))
            }
          }
        | _ => raise(ParseError("Expected opening parenthesis"))
        }
      }
    | Some(LParen) => {
        let _ = lex();
        let bits = [];
        let it = ref(None)
        while {it := parseExp(); it.contents->Option.isSome} {
          Array.push(bits, it.contents->Option.getUnsafe)
        }
        switch lex() {
        | Some(RParen) => Some(Compound({subexps:bits}))
        | _ => raise(ParseError("Expected closing parenthesis"))
        }
      }
    | _ => None
    }
  }
  switch parseExp() {
  | exception ParseError(s) => Error(s)
  | None => Error("No expression to parse")
  | Some(e) => Ok((e,cur.contents)) 
  }
}
let testParse = (str : string, scope: array<string>) => {
  let gen = ref(0)
  switch parse(str,~scope=scope,~gen=gen) {
  | Ok(t,_) => {Console.log(t); Some(t)}
  | Error(e) => {Console.log(e); None}
  }
}
