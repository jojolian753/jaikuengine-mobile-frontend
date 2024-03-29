/*
 *  DBD::mSQL - DBI driver for the mysql database
 *
 *  Copyright (c) 2003       Rudolf Lippan
 *  Copyright (c) 1997-2003  Jochen Wiedmann
 *
 *  Based on DBD::Oracle; DBD::Oracle is
 *
 *  Copyright (c) 1994,1995  Tim Bunce
 *
 *  You may distribute this under the terms of either the GNU General Public
 *  License or the Artistic License, as specified in the Perl README file.
 *
 *  $Id: dbdimp.h 6305 2006-05-17 22:29:38Z capttofu $
 */

/*
 *  Header files we use
 */
#include <DBIXS.h>  /* installed by the DBI module                        */
#include <mysql.h>  /* Comes with MySQL-devel */
#include <mysqld_error.h>  /* Comes MySQL */
#include <errmsg.h> /* Comes with MySQL-devel */

/*
 * This is the version of MySQL wherer
 * the server will be used to process prepare
 * statements as opposed to emulation in the driver
*/
#define SERVER_PREPARE_VERSION 40103

/*
 *  The following are return codes passed in $h->err in case of
 *  errors by DBD::mysql.
 */
enum errMsgs {
    JW_ERR_CONNECT = 1,
    JW_ERR_SELECT_DB,
    JW_ERR_STORE_RESULT,
    JW_ERR_NOT_ACTIVE,
    JW_ERR_QUERY,
    JW_ERR_FETCH_ROW,
    JW_ERR_LIST_DB,
    JW_ERR_CREATE_DB,
    JW_ERR_DROP_DB,
    JW_ERR_LIST_TABLES,
    JW_ERR_LIST_FIELDS,
    JW_ERR_LIST_FIELDS_INT,
    JW_ERR_LIST_SEL_FIELDS,
    JW_ERR_NO_RESULT,
    JW_ERR_NOT_IMPLEMENTED,
    JW_ERR_ILLEGAL_PARAM_NUM,
    JW_ERR_MEM,
    JW_ERR_LIST_INDEX,
    JW_ERR_SEQUENCE,
    AS_ERR_EMBEDDED,
    TX_ERR_AUTOCOMMIT,
    TX_ERR_COMMIT,
    TX_ERR_ROLLBACK
};


/*
 *  Internal constants, used for fetching array attributes
 */
enum av_attribs {
    AV_ATTRIB_NAME = 0,
    AV_ATTRIB_TABLE,
    AV_ATTRIB_TYPE,
    AV_ATTRIB_SQL_TYPE,
    AV_ATTRIB_IS_PRI_KEY,
    AV_ATTRIB_IS_NOT_NULL,
    AV_ATTRIB_NULLABLE,
    AV_ATTRIB_LENGTH,
    AV_ATTRIB_IS_NUM,
    AV_ATTRIB_TYPE_NAME,
    AV_ATTRIB_PRECISION,
    AV_ATTRIB_SCALE,
    AV_ATTRIB_MAX_LENGTH,
    AV_ATTRIB_IS_KEY,
    AV_ATTRIB_IS_BLOB,
    AV_ATTRIB_IS_AUTO_INCREMENT,
    AV_ATTRIB_LAST         /*  Dummy attribute, never used, for allocation  */
};                         /*  purposes only                                */


/*
 *  This is our part of the driver handle. We receive the handle as
 *  an "SV*", say "drh", and receive a pointer to the structure below
 *  by declaring
 *
 *    D_imp_drh(drh);
 *
 *  This declares a variable called "imp_drh" of type
 *  "struct imp_drh_st *".
 */
typedef struct imp_drh_embedded_st {
    int state;
    SV * args;
    SV * groups;
} imp_drh_embedded_t;

struct imp_drh_st {
    dbih_drc_t com;         /* MUST be first element in structure   */
#if defined(DBD_MYSQL_EMBEDDED)
    imp_drh_embedded_t embedded;     /* */
#endif
};


/*
 *  Likewise, this is our part of the database handle, as returned
 *  by DBI->connect. We receive the handle as an "SV*", say "dbh",
 *  and receive a pointer to the structure below by declaring
 *
 *    D_imp_dbh(dbh);
 *
 *  This declares a variable called "imp_dbh" of type
 *  "struct imp_dbh_st *".
 */
struct imp_dbh_st {
    dbih_dbc_t com;         /*  MUST be first element in structure   */

    MYSQL mysql;
    int has_transactions;   /*  boolean indicating support for
			     *  transactions, currently always
			     *  TRUE for MySQL and always FALSE
			     *  for mSQL.
			     */
    bool auto_reconnect;
    struct {
	    unsigned int auto_reconnects_ok;
	    unsigned int auto_reconnects_failed;
    } stats;
    unsigned short int  bind_type_guessing;
    int use_mysql_use_result; /* TRUE if execute should use
                               * mysql_use_result rather than
                               * mysql_store_result
                               */
    int use_server_side_prepare;
    int has_autodetect_prepare;
};


/*
 *  The bind_param method internally uses this structure for storing
 *  parameters.
 */
typedef struct imp_sth_ph_st {
    SV* value;
    int type;
} imp_sth_ph_t;

/*
 *  The bind_param method internally uses this structure for storing
 *  parameters.
 */
typedef struct imp_sth_phb_st {
    union
    {
      long lval;
      double dval;
    } numeric_val;
    unsigned long   length;
    char            is_null;
} imp_sth_phb_t;

/*
 *  The dbd_describe uses this structure for storing
 *  fields meta info.
 *  Added ddata, ldata, lldata for accomodate
 *  being able to use different data types
 *  12.02.20004 PMG
 */
typedef struct imp_sth_fbh_st {
    unsigned long  length;
    bool           is_null;
    char           * data;
    double        ddata;
    long          ldata;

} imp_sth_fbh_t;


typedef struct imp_sth_fbind_st {
   unsigned long   * length;
   char            * is_null;
} imp_sth_fbind_t;


/*
 *  Finally our part of the statement handle. We receive the handle as
 *  an "SV*", say "dbh", and receive a pointer to the structure below
 *  by declaring
 *
 *    D_imp_sth(sth);
 *
 *  This declares a variable called "imp_sth" of type
 *  "struct imp_sth_st *".
 */
struct imp_sth_st {
    dbih_stc_t com;       /* MUST be first element in structure     */

#if (MYSQL_VERSION_ID >= SERVER_PREPARE_VERSION)
    MYSQL_STMT       *stmt;
    MYSQL_BIND       *bind;
    MYSQL_BIND       *buffer;
    imp_sth_phb_t    *fbind;
    imp_sth_fbh_t    *fbh;
    int              has_been_bound;
    int use_server_side_prepare;     /* does server support new binary protocol */
#endif

    MYSQL_RES* result;       /* result                                 */
    int currow;           /* number of current row                  */
    int fetch_done;       /* mark that fetch done                   */
    my_ulonglong row_num;         /* total number of rows                   */

    int   done_desc;      /* have we described this sth yet ?	    */
    long  long_buflen;    /* length for long/longraw (if >0)	    */
    bool  long_trunc_ok;  /* is truncating a long an error	    */
    my_ulonglong insertid; /* ID of auto insert                      */
    imp_sth_ph_t* params; /* Pointer to parameter array             */
    AV* av_attr[AV_ATTRIB_LAST];/*  For caching array attributes        */
    int   use_mysql_use_result;  /*  TRUE if execute should use     */
                          /* mysql_use_result rather than           */
                          /* mysql_store_result */
};


/*
 *  And last, not least: The prototype definitions.
 *
 * These defines avoid name clashes for multiple statically linked DBD's	*/
#define dbd_init		mysql_dr_init
#define dbd_db_login		mysql_db_login
#define dbd_db_do		mysql_db_do
#define dbd_db_commit		mysql_db_commit
#define dbd_db_rollback		mysql_db_rollback
#define dbd_db_disconnect	mysql_db_disconnect
#define dbd_db_destroy		mysql_db_destroy
#define dbd_db_STORE_attrib	mysql_db_STORE_attrib
#define dbd_db_FETCH_attrib	mysql_db_FETCH_attrib
#define dbd_st_prepare		mysql_st_prepare
#define dbd_st_execute		mysql_st_execute
#define dbd_st_fetch		mysql_st_fetch
#define dbd_st_finish		mysql_st_finish
#define dbd_st_destroy		mysql_st_destroy
#define dbd_st_blob_read	mysql_st_blob_read
#define dbd_st_STORE_attrib	mysql_st_STORE_attrib
#define dbd_st_FETCH_attrib	mysql_st_FETCH_attrib
#define dbd_st_FETCH_internal	mysql_st_FETCH_internal
#define dbd_describe		mysql_describe
#define dbd_bind_ph		mysql_bind_ph
#define BindParam		mysql_st_bind_param
#define mymsql_constant         mysql_constant
#define do_warn			mysql_dr_warn
#define do_error		mysql_dr_error
#define dbd_db_type_info_all    mysql_db_type_info_all
#define dbd_db_quote            mysql_db_quote

#ifdef DBD_MYSQL_INSERT_ID_IS_GOOD /* prototype was broken in some versions of dbi */
#define dbd_db_last_insert_id   mysql_db_last_insert_id
#endif

#include <dbd_xsh.h>
void	 do_error (SV* h, int rc, const char *what);
SV	*dbd_db_fieldlist (MYSQL_RES* res);

void    dbd_preparse (imp_sth_t *imp_sth, SV *statement);
my_ulonglong mysql_st_internal_execute(SV*, SV*, SV*, int, imp_sth_ph_t*, MYSQL_RES**,
			      MYSQL*, int);

#if MYSQL_VERSION_ID >= SERVER_PREPARE_VERSION
my_ulonglong mysql_st_internal_execute41(SV*, SV*, SV*, int, imp_sth_ph_t*, MYSQL_RES**,
                              MYSQL*, int, MYSQL_STMT*, MYSQL_BIND*, int*);

int mysql_st_clean_cursor(SV*, imp_sth_t*);
#endif

#if defined(DBD_MYSQL_EMBEDDED)
int count_embedded_options(char *);
char ** fill_out_embedded_options(char *, int , int , int );
int free_embedded_options(char **, int);
/* We have to define dbd_discon_all method for mysqlEmb driver at least
   to be able to stop embedded server properly */
#define dbd_discon_all dbd_discon_all
#endif

AV* dbd_db_type_info_all (SV* dbh, imp_dbh_t* imp_dbh);
SV* dbd_db_quote(SV*, SV*, SV*);
extern MYSQL* mysql_dr_connect(SV*, MYSQL*, char*, char*, char*, char*, char*,
			       char*, imp_dbh_t*);

extern int mysql_db_reconnect(SV*);
