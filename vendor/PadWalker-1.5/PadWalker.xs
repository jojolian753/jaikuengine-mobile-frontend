#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* For development testing */
#ifdef PADWALKER_DEBUGGING
# define debug_print(x) printf x
#else
# define debug_print(x)
#endif

/* For debugging */
#ifdef PADWALKER_DEBUGGING
char *
cxtype_name(U32 cx_type)
{
  switch(cx_type & CXTYPEMASK)
  {
    case CXt_NULL:   return "null";
    case CXt_SUB:    return "sub";
    case CXt_EVAL:   return "eval";
    case CXt_LOOP:   return "loop";
    case CXt_SUBST:  return "subst";
    case CXt_BLOCK:  return "block";
    case CXt_FORMAT: return "format";

    default:         debug_print(("Unknown context type 0x%lx\n", cx_type));
                                         return "(unknown)";
  }
}

void
show_cxstack(void)
{
    I32 i;
    for (i = cxstack_ix; i>=0; --i)
    {
        printf(" =%ld= %s (%lx)", (long)i,
            cxtype_name(CxTYPE(&cxstack[i])), cxstack[i].blk_oldcop->cop_seq);
        if (CxTYPE(&cxstack[i]) == CXt_SUB) {
              CV *cv = cxstack[i].blk_sub.cv;
              printf("\t%s", (cv && CvGV(cv)) ? GvNAME(CvGV(cv)) :"(null)");
        }
        printf("\n");
    }
}
#else
# define show_cxstack()
#endif

#ifndef SvOURSTASH
# ifdef OURSTASH
#  define SvOURSTASH OURSTASH
# else
#  define SvOURSTASH GvSTASH
# endif
#endif

#ifndef COP_SEQ_RANGE_LOW
#  define COP_SEQ_RANGE_LOW(sv)                  U_32(SvNVX(sv))
#endif
#ifndef COP_SEQ_RANGE_HIGH
#  define COP_SEQ_RANGE_HIGH(sv)                 U_32(SvUVX(sv))
#endif


/* Originally stolen from pp_ctl.c; now significantly different */

I32
dopoptosub_at(pTHX_ PERL_CONTEXT *cxstk, I32 startingblock)
{
    dTHR;
    I32 i;
    PERL_CONTEXT *cx;
    for (i = startingblock; i >= 0; i--) {
        cx = &cxstk[i];
        switch (CxTYPE(cx)) {
        default:
            continue;
        case CXt_SUB:
        /* In Perl 5.005, formats just used CXt_SUB */
#ifdef CXt_FORMAT
       case CXt_FORMAT:
#endif
            debug_print(("**dopoptosub_at: found sub #%ld\n", (long)i));
            return i;
        }
    }
        debug_print(("**dopoptosub_at: not found #%ld\n", (long)i));
    return i;
}

I32
dopoptosub(pTHX_ I32 startingblock)
{
    dTHR;
    return dopoptosub_at(aTHX_ cxstack, startingblock);
}

/* This function is based on the code of pp_caller */
PERL_CONTEXT*
upcontext(pTHX_ I32 count, COP **cop_p, PERL_CONTEXT **ccstack_p,
                                I32 *cxix_from_p, I32 *cxix_to_p)
{
    PERL_SI *top_si = PL_curstackinfo;
    I32 cxix = dopoptosub(aTHX_ cxstack_ix);
    PERL_CONTEXT *ccstack = cxstack;

    if (cxix_from_p) *cxix_from_p = cxstack_ix+1;
    if (cxix_to_p)   *cxix_to_p   = cxix;
    for (;;) {
        /* we may be in a higher stacklevel, so dig down deeper */
        while (cxix < 0 && top_si->si_type != PERLSI_MAIN) {
            top_si  = top_si->si_prev;
            ccstack = top_si->si_cxstack;
            cxix = dopoptosub_at(aTHX_ ccstack, top_si->si_cxix);
                        if (cxix_to_p && cxix_from_p) *cxix_from_p = *cxix_to_p;
                        if (cxix_to_p) *cxix_to_p = cxix;
        }
        if (cxix < 0 && count == 0) {
                    if (ccstack_p) *ccstack_p = ccstack;
            return (PERL_CONTEXT *)0;
                }
        else if (cxix < 0)
            return (PERL_CONTEXT *)-1;
        if (PL_DBsub && cxix >= 0 &&
                ccstack[cxix].blk_sub.cv == GvCV(PL_DBsub))
            count++;
        if (!count--)
            break;

        if (cop_p) *cop_p = ccstack[cxix].blk_oldcop;
        cxix = dopoptosub_at(aTHX_ ccstack, cxix - 1);
                        if (cxix_to_p && cxix_from_p) *cxix_from_p = *cxix_to_p;
                        if (cxix_to_p) *cxix_to_p = cxix;
    }
    if (ccstack_p) *ccstack_p = ccstack;
    return &ccstack[cxix];
}

/* end thievery */

SV*
fetch_from_stash(HV *stash, char *name_str, U32 name_len)
{
    /* This isn't the most efficient approach, but it has
     * the advantage that it uses documented API functions. */
    char *package_name = HvNAME(stash);
    char *qualified_name;
    SV *ret = 0;  /* Initialise to silence spurious compiler warning */
    
    New(0, qualified_name, strlen(package_name) + 2 + name_len, char);
    strcpy(qualified_name, package_name);
    strcat(qualified_name, "::");
    strcat(qualified_name, name_str+1);

    debug_print(("fetch_from_stash: Looking for %c%s\n",
                 name_str[0], qualified_name));
    switch (name_str[0]) {
      case '$': ret =       get_sv(qualified_name, FALSE); break;
      case '@': ret = (SV*) get_av(qualified_name, FALSE); break;
      case '%': ret = (SV*) get_hv(qualified_name, FALSE); break;
      default:  die("PadWalker: variable '%s' of unknown type", name_str);
    }
    if (ret)
      debug_print(("%s\n", sv_peek(ret)));
    else
      /* I don't _think_ this should ever happen */
      debug_print(("XXXX - Variable %c%s not found\n",
                   name_str[0], qualified_name));
    Safefree(qualified_name);
    return ret;
}

void
pads_into_hash(AV* pad_namelist, AV* pad_vallist, HV* my_hash, HV* our_hash, U32 valid_at_seq)
{
    I32 i;

    debug_print(("pads_into_hash(%p, %p, ..)\n",
        (void*)pad_namelist, (void*) pad_vallist));

    for (i=av_len(pad_namelist); i>=0; --i) {
      SV** name_ptr = av_fetch(pad_namelist, i, 0);

      if (name_ptr) {
        SV*   name_sv = *name_ptr;

        if (SvPOKp(name_sv)) {
          char* name_str = SvPVX(name_sv);

        debug_print(("** %s (%lx,%lx) [%lx]%s\n", name_str,
               COP_SEQ_RANGE_LOW(name_sv), COP_SEQ_RANGE_HIGH(name_sv), valid_at_seq,
               SvFAKE(name_sv) ? " <fake>" : ""));
        
        /* Check that this variable is valid at the cop_seq
         * specified, by peeking into the NV and IV slots
         * of the name sv. (This must be one of those "breathtaking
         * optimisations" mentioned in the Panther book).

         * Anonymous subs are stored here with a name of "&",
         * so also check that the name is longer than one char.
         * (Note that the prefix letter is here as well, so a
         * valid variable will _always_ be >1 char)

         * We ignore 'our' variables, since you can always dig
         * them out of the stash directly.
         */

        if ((SvFAKE(name_sv) || 0 == valid_at_seq ||
            (valid_at_seq <= COP_SEQ_RANGE_HIGH(name_sv) &&
            valid_at_seq > COP_SEQ_RANGE_LOW(name_sv))) &&
            strlen(name_str) > 1 )

          {
            SV **val_ptr, *val_sv;
            U32 name_len = strlen(name_str);
            bool is_our = ((SvFLAGS(name_sv) & SVpad_OUR) != 0);

            debug_print(((is_our ? "**     FOUND OUR %s\n"
                                 : "**     FOUND MY %s\n"), name_str));

            if (   hv_exists(my_hash, name_str, name_len)
                || hv_exists(our_hash, name_str, name_len))
            {
              debug_print(("** key already exists - ignoring!\n"));
            }
            else {
              if (is_our) {
                val_sv = fetch_from_stash(SvOURSTASH(name_sv), name_str, name_len);
                if (!val_sv) {
                    debug_print(("Value of our variable is undefined\n"));
                    val_sv = &PL_sv_undef;
                }
              }
              else
              {
                val_ptr = pad_vallist ? av_fetch(pad_vallist, i, 0) : 0;
                val_sv = val_ptr ? *val_ptr : &PL_sv_undef;
              }

              hv_store((is_our ? our_hash : my_hash), name_str, name_len,
                       newRV_inc(val_sv), 0);
            }
          }
        }
      }
    }
}

void
padlist_into_hash(AV* padlist, HV* my_hash, HV* our_hash, U32 valid_at_seq, long depth)
{
    AV *pad_namelist, *pad_vallist;
    
    if (depth == 0) depth = 1;

    /* We blindly deref this, cos it's always there (AFAIK!) */
    pad_namelist = (AV*) *av_fetch(padlist, 0, FALSE);
    pad_vallist  = (AV*) *av_fetch(padlist, depth, FALSE);

    pads_into_hash(pad_namelist, pad_vallist, my_hash, our_hash, valid_at_seq);
}

void
context_vars(PERL_CONTEXT *cx, HV* my_ret, HV* our_ret, U32 seq, CV *cv)
{
    /* If cx is null, we take that to mean that we should look
     * at the cv instead
     */

    debug_print(("**context_vars(%p, %p, %p, 0x%lx)\n",
                 (void*)cx, (void*)my_ret, (void*)our_ret, (long)seq));
    if (cx == (PERL_CONTEXT*)-1)
        croak("Not nested deeply enough");

    else {
        CV*  cur_cv = cx ? cx->blk_sub.cv           : cv;
        long depth  = cx ? cx->blk_sub.olddepth + 1 : 1;

        if (!cur_cv)
            die("panic: Context has no CV!\n");
    
        while (cur_cv) {
            debug_print(("\tcv name = %s; depth=%ld\n",
                    CvGV(cur_cv) ? GvNAME(CvGV(cur_cv)) :"(null)", depth));
            if (CvPADLIST(cur_cv))
                padlist_into_hash(CvPADLIST(cur_cv), my_ret, our_ret, seq, depth);
            cur_cv = CvOUTSIDE(cur_cv);
            if (cur_cv) depth  = CvDEPTH(cur_cv);
        }
    }
}

void
do_peek(I32 uplevel, HV* my_hash, HV* our_hash)
{
    PERL_CONTEXT *cx, *ccstack;
    COP *cop = 0;
    I32 cxix_from, cxix_to, i;
    bool first_eval = TRUE;

    show_cxstack();
    if (PL_curstackinfo->si_type != PERLSI_MAIN)
          debug_print(("!! We're in a higher stack level\n"));

    cx = upcontext(aTHX_ uplevel, &cop, &ccstack, &cxix_from, &cxix_to);
    debug_print(("** cxix = (%ld,%ld)\n", cxix_from, cxix_to));
    if (cop == 0) {
           debug_print(("**Setting cop to PL_curcop\n"));
           cop = PL_curcop;
        }
    debug_print(("**Cop file = %s\n", CopFILE(cop)));

    context_vars(cx, my_hash, our_hash, cop->cop_seq, PL_main_cv);

    for (i = cxix_from-1; i > cxix_to; --i) {
        debug_print(("** CxTYPE = %s (cxix = %ld)\n",
            cxtype_name(CxTYPE(&ccstack[i])), i));
        switch (CxTYPE(&ccstack[i])) {
        case CXt_EVAL:
            debug_print(("\told_op_type = %ld\n", ccstack[i].blk_eval.old_op_type));
            switch(ccstack[i].blk_eval.old_op_type) {
            case OP_ENTEREVAL:
                if (first_eval) {
                   context_vars(0, my_hash, our_hash, cop->cop_seq, ccstack[i].blk_eval.cv);
                   first_eval = FALSE;
                }
                context_vars(0, my_hash, our_hash, ccstack[i].blk_oldcop->cop_seq,
                                                ccstack[i].blk_eval.cv);
                break;
            case OP_REQUIRE:
            case OP_DOFILE:
                debug_print(("blk_eval.cv = %p\n", (void*) ccstack[i].blk_eval.cv));
                if (first_eval)
                   context_vars(0, my_hash, our_hash,
                    cop->cop_seq, ccstack[i].blk_eval.cv);
                return;
                /* If it's OP_ENTERTRY, we skip this altogether. */
            }
            break;

        case CXt_SUB:
#ifdef CXt_FORMAT
        case CXt_FORMAT:
#endif
                Perl_die(aTHX_ "PadWalker: internal error");
                    exit(EXIT_FAILURE);
        }
    }
}

void
get_closed_over(CV *cv, HV *hash, HV *indices)
{
    I32 i;
    U32 val_depth = CvDEPTH(cv) ? CvDEPTH(cv) : 1;
    AV *pad_namelist = (AV*) *av_fetch(CvPADLIST(cv), 0, FALSE);
    AV *pad_vallist  = (AV*) *av_fetch(CvPADLIST(cv), val_depth, FALSE);

    debug_print(("av_len(CvPADLIST(cv)) = %ld\n", av_len(CvPADLIST(cv)) ));
    
    for (i=av_len(pad_namelist); i>=0; --i) {
      SV** name_ptr = av_fetch(pad_namelist, i, 0);

      if (name_ptr && SvPOKp(*name_ptr)) {
        SV*   name_sv   = *name_ptr;
        char* name_str  = SvPVX(name_sv);
        STRLEN name_len = strlen(name_str);
        
        if (SvFAKE(name_sv) && 0 == (SvFLAGS(name_sv) & SVpad_OUR)) {
            SV **val   = av_fetch(pad_vallist, i, 0);
            SV *val_sv = val ? *val : &PL_sv_undef;
#ifdef PADWALKER_DEBUGGING
            debug_print(("Found a fake slot: %s\n", name_str));
            if (val == 0)
                debug_print(("value is null\n"));
            else
                sv_dump(*val);
#endif
            hv_store(hash, name_str, name_len, newRV_inc(val_sv), 0);
            if (indices) {
              /* Create a temporary SV as a way of getting perl to 
               * stringify 'i' for us. */
              SV *i_sv = newSViv(i);
              hv_store_ent(indices, i_sv, newRV_inc(val_sv), 0);
              SvREFCNT_dec(i_sv);
            }
        }
      }
    }
}

char *
get_var_name(CV *cv, SV *var)
{
    I32 i;
    U32 val_depth = CvDEPTH(cv) ? CvDEPTH(cv) : 1;
    AV *pad_namelist = (AV*) *av_fetch(CvPADLIST(cv), 0, FALSE);
    AV *pad_vallist  = (AV*) *av_fetch(CvPADLIST(cv), val_depth, FALSE);

    for (i=av_len(pad_namelist); i>=0; --i) {
      SV** name_ptr = av_fetch(pad_namelist, i, 0);

      if (name_ptr && SvPOKp(*name_ptr)) {
        SV*   name_sv   = *name_ptr;
        char* name_str  = SvPVX(name_sv);
        
        SV **val   = av_fetch(pad_vallist, i, 0);
        if (val && (*val == var))
          return name_str;
      }
    }
    return 0;
}

CV *
up_cv(I32 uplevel, const char * caller_name)
{
    PERL_CONTEXT *cx, *ccstack;
    I32 cxix_from, cxix_to, i;

    if (uplevel < 0)
      croak("%s: sub is < 0", caller_name);

    cx = upcontext(aTHX_ uplevel, 0, &ccstack, &cxix_from, &cxix_to);
    if (cx == (PERL_CONTEXT *)-1) {
      croak("%s: Not nested deeply enough", caller_name);
      return 0;  /* NOT REACHED, but stop picky compilers from whining */
    }
    else if (cx)
      return cx->blk_sub.cv;
      
    else {

      for (i = cxix_from-1; i > cxix_to; --i)
        if (CxTYPE(&ccstack[i]) == CXt_EVAL) {
          I32 old_op_type = ccstack[i].blk_eval.old_op_type;
          if (old_op_type == OP_REQUIRE || old_op_type == OP_DOFILE)
            return ccstack[i].blk_eval.cv;
        }

      return PL_main_cv;
    }
}


MODULE = PadWalker              PACKAGE = PadWalker
PROTOTYPES: DISABLE             

void
peek_my(uplevel)
I32 uplevel;
 PREINIT:
    HV* ret = newHV();
    HV* ignore = newHV();
 PPCODE:
    do_peek(uplevel, ret, ignore);
    SvREFCNT_dec((SV*) ignore);
    EXTEND(SP, 1);
    PUSHs(sv_2mortal(newRV_noinc((SV*)ret)));

void
peek_our(uplevel)
I32 uplevel;
 PREINIT:
    HV* ret = newHV();
    HV* ignore = newHV();
 PPCODE:
    do_peek(uplevel, ignore, ret);
    SvREFCNT_dec((SV*) ignore);
    EXTEND(SP, 1);
    PUSHs(sv_2mortal(newRV_noinc((SV*)ret)));


void
peek_sub(cv)
CV* cv;
  PREINIT:
    HV* ret = newHV();
    HV* ignore = newHV();
  PPCODE:
    padlist_into_hash(CvPADLIST(cv), ret, ignore, 0, CvDEPTH(cv));
    SvREFCNT_dec((SV*) ignore);
    EXTEND(SP, 1);
    PUSHs(sv_2mortal(newRV_noinc((SV*)ret)));

void
closed_over(cv)
CV* cv;
  PREINIT:
    HV* ret = newHV();
    HV* targs;
  PPCODE:
    if (GIMME_V == G_ARRAY) {
        targs = newHV();
        get_closed_over(cv, ret, targs);
    
        EXTEND(SP, 2);
        PUSHs(sv_2mortal(newRV_noinc((SV*)ret)));
        PUSHs(sv_2mortal(newRV_noinc((SV*)targs)));
    }
    else {
        get_closed_over(cv, ret, 0);
        
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(newRV_noinc((SV*)ret)));
    }

char*
var_name(sub, var_ref)
SV* sub;
SV* var_ref;
  PREINIT:
    SV *cv;
  CODE:
    if (!SvROK(var_ref))
      croak("Usage: PadWalker::var_name(sub, var_ref)");
      
    if (SvROK(sub)) {
      cv = SvRV(sub);
      if (SvTYPE(cv) != SVt_PVCV)
        croak("PadWalker::var_name: sub is neither a CODE reference nor a number");
    } else
      cv = (SV *) up_cv(SvIV(sub), "PadWalker::upcontext");
    
    RETVAL = get_var_name((CV *) cv, SvRV(var_ref));
  OUTPUT:
    RETVAL

void
_upcontext(uplevel)
I32 uplevel
  PPCODE:
    /* I'm not sure why this is here, but I'll leave it in case
         * somebody is using it in an insanely evil way. */
    XPUSHs(sv_2mortal(newSViv((U32)upcontext(aTHX_ uplevel, 0, 0, 0, 0))));
