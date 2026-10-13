import java.nio.file.*;
import java.sql.*;
import java.util.*;

class TestAreaMembership {
    static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    static long count(Statement s, String query) throws SQLException {
        try (var r=s.executeQuery(query)) { r.next(); return r.getLong(1); }
    }
    static void loadFixture(Statement s, boolean empty) throws SQLException {
        s.execute("CREATE TABLE input_fixture (DATAFLOW VARCHAR, MEASURE VARCHAR, TIME_PERIOD INTEGER, "
            +"VALUE_ADDED_SOURCE_AREA VARCHAR, VALUE_ADDED_SOURCE_ACTIVITY VARCHAR, FINAL_DEMAND_AREA VARCHAR, "
            +"FINAL_DEMAND_ACTIVITY VARCHAR, OBS_VALUE DOUBLE, UNIT_MEASURE VARCHAR, UNIT_MULT INTEGER, FREQ VARCHAR)");
        if (!empty) s.execute("INSERT INTO input_fixture VALUES "
            +"('FDVA','M',2022,'USA','X','CAN','Y',1.5,'USD',6,'A'),"
            +"('FDVA','M',2022,'USA','X','CAN','Y',NULL,'USD',6,'A'),"
            +"(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL),"
            +"('FDVA','M',2022,'AGO','X','COD','Y',1.0,'USD',6,'A'),"
            +"('FDVA','M',2022,'STP','X','ARE','Y',2.0,'USD',6,'A')");
    }
    static String sql(Path root, Path csv) throws Exception {
        return Files.readString(root.resolve("ontop/load.sql"))
            .replace("FROM read_csv('/data/FDVA.csv.zst', header=true)","FROM input_fixture")
            .replace("/opt/ontop/input/tiva-area-mapping.csv",csv.toString().replace("'","''"));
    }
    public static void main(String[] args) throws Exception {
        Class.forName("org.duckdb.DuckDBDriver");
        Path root=Path.of(args[0]).toAbsolutePath();
        Path csv=root.resolve("ontop/tiva-area-mapping.csv");
        String script=sql(root,csv);
        for (boolean empty:new boolean[]{false,true}) {
            try (var c=DriverManager.getConnection("jdbc:duckdb:"); var s=c.createStatement()) {
                loadFixture(s,empty);
                s.execute(script);
                check(count(s,"SELECT count(*) FROM tiva")== (empty?0:5),"Fact row count");
                check(count(s,"SELECT count(*) FROM tiva_area_membership")==311,"Membership count");
                List<String> nafta=new ArrayList<>();
                try(var r=s.executeQuery("SELECT MEMBER_CODE FROM tiva_area_membership WHERE AREA_CODE='NAFTA' ORDER BY MEMBER_CODE")) {
                    while(r.next())nafta.add(r.getString(1));
                }
                check(nafta.equals(List.of("CAN","MEX","USA")),"NAFTA members");
                check(count(s,"SELECT count(*) FROM tiva_area_membership WHERE AREA_CODE IN ('W','D')")==0,"No invented World/Domestic edges");
                check(count(s,"SELECT count(*) FROM tiva_area_membership WHERE MEMBER_CODE='WXD' AND MEMBER_KIND='residual'")==2,"Residual preserved");
                check(count(s,"SELECT count(*) FROM tiva_area_membership WHERE AREA_CODE='G20' AND MEMBER_CODE='EU27_2020' AND MEMBER_KIND='aggregate'")==1,"Nested EU preserved");
                check(count(s,"SELECT count(*) FROM tiva_area_membership m LEFT JOIN tiva_area a ON m.AREA_CODE=a.CODE LEFT JOIN tiva_area b ON m.MEMBER_CODE=b.CODE WHERE a.CODE IS NULL OR b.CODE IS NULL")==0,"Every membership endpoint has concept metadata");
                check(count(s,"SELECT count(*) FROM duckdb_indexes()")==13,"Original indexes plus country lookup index");
                s.execute(script);
                check(count(s,"SELECT count(*) FROM tiva_area_membership")==311,"Rebuild stable");
                check(count(s,"SELECT count(*) FROM tiva_area_country")==(empty?408:412),"Flattened country pair count");
                check(count(s,"SELECT count(*) FROM tiva_area_country WHERE AREA_CODE='G20' AND COUNTRY_CODE='FRA'")==1,"Nested/direct country paths deduplicated");
                check(count(s,"SELECT count(*) FROM tiva_area_country WHERE AREA_CODE='CAN' AND COUNTRY_CODE='CAN'")==1,"Country identity link");
                check(count(s,"SELECT count(*) FROM tiva_area_country WHERE AREA_CODE IN ('D','W','WXD') OR COUNTRY_CODE='WXD'")==0,"No guessed country links");
                check(count(s,"SELECT count(*) FROM tiva_area_country WHERE COUNTRY_CODE='CAN'")==5,"Reverse country lookup");
                check(count(s,"SELECT count(*) FROM tiva_area_country WHERE AREA_CODE IN ('AGO','COD','STP','ARE') AND AREA_CODE=COUNTRY_CODE")== (empty?0:4),"2025 country identity links");
                // A malformed or missing CSV must fail and roll back the rebuild.
                Path bad=Files.createTempFile("tiva-membership-invalid-", ".csv");
                try {
                    String contents=Files.readString(csv);
                    String duplicate=contents.lines().filter(line->line.startsWith("NAFTA,")).findFirst().orElseThrow();
                    for(String invalid:new String[]{contents+duplicate+"\n", contents.replace("NAFTA,CAN,economy","NAFTA,CAN,invalid")}) {
                        Files.writeString(bad,invalid);
                        boolean failed=false;
                        try(var failing=c.createStatement()){failing.execute(sql(root,bad));}catch(SQLException expected){failed=true;try(var rollback=c.createStatement()){rollback.execute("ROLLBACK");}}
                        check(failed,"Invalid CSV must fail");
                        check(count(s,"SELECT count(*) FROM tiva_area_membership")==311,"Previous table survives rollback");
                    }
                    Files.delete(bad);
                    boolean failed=false;
                    try(var failing=c.createStatement()){failing.execute(sql(root,bad));}catch(SQLException expected){failed=true;try(var rollback=c.createStatement()){rollback.execute("ROLLBACK");}}
                    check(failed,"Missing CSV must fail");
                    check(count(s,"SELECT count(*) FROM tiva_area_membership")==311,"Previous table survives missing CSV");
                } finally {Files.deleteIfExists(bad);}
            }
        }
        System.out.println("PASS: membership extraction, concepts, nested/residual areas, null/empty facts, indexes, rebuilds and rollback.");
    }
}
