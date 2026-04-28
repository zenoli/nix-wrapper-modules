{
  pkgs,
  self,
  tlib,
  ...
}:
let
  inherit (tlib)
    areEqual
    test
    ;
  testfunctor = self.lib.makeCustomizable "test" { } (v: { value = v; }) { some = "args"; };

  testfunctor2 = testfunctor.test (lp: {
    more = lp.some;
  });
  testfunctor3 = testfunctor.test (lp: {
    more = "with overriding";
  });
  testfunctor4 = testfunctor3.test { again = "testing"; };
in

test "makeCustomizable-test" [
  (areEqual "args" testfunctor.value.some)

  (areEqual "args" testfunctor2.value.some)
  (areEqual "args" testfunctor2.value.more)

  (areEqual "args" testfunctor3.value.some)
  (areEqual "with overriding" testfunctor3.value.more)

  (areEqual "args" testfunctor4.value.some)
  (areEqual "with overriding" testfunctor4.value.more)
  (areEqual "testing" testfunctor4.value.again)
]
